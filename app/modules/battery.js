// Command line interactors
const { exec } = require('node:child_process')
const { log, alert, wait } = require( './helpers' )
const { USER } = process.env
const path = require('path')
const path_fix = 'PATH=$PATH:/bin:/usr/bin:/usr/local/bin:/usr/sbin:/opt/homebrew:/usr/bin/'
const venti = `${ path_fix } venti`
const { app } = require( 'electron' )
const shell_options = {
    shell: '/bin/bash',
    env: { ...process.env, PATH: `${ process.env.PATH }:/usr/local/bin` }
}

// Execute without sudo
const exec_async_no_timeout = command => new Promise( ( resolve, reject ) => {

    log( `Executing ${ command }` )

    exec( command, shell_options, ( error, stdout, stderr ) => {

        if( error ) return reject( error, stderr, stdout )
        if( stderr ) return reject( stderr )
        if( stdout ) return resolve( stdout )

    } )

} )

const exec_async = ( command, timeout_in_ms=2000, throw_on_timeout=false ) => Promise.race( [
    exec_async_no_timeout( command ),
    wait( timeout_in_ms ).then( () => {
        if( throw_on_timeout ) throw new Error( `${ command } timed out` )
    } )
] )

// Execute with sudo using direct AppleScript (more reliable)
const exec_sudo_async = async command => new Promise(async (resolve, reject) => {
    try {
        log(`Sudo executing command via AppleScript: ${command}`)
        
        // Escape double quotes in the command
        const escapedCommand = command.replace(/"/g, '\\"')
        
        // Create AppleScript to request admin privileges
        const appleScript = `do shell script "${escapedCommand}" with administrator privileges`
        
        exec(`osascript -e '${appleScript}'`, shell_options, (error, stdout, stderr) => {
            if (error) {
                if (error.message && error.message.includes('User canceled')) {
                    return reject(new Error('Authentication canceled by user'))
                }
                return reject(error)
            }
            if (stderr) return reject(stderr)
            return resolve(stdout || true)
        })
    } catch (err) {
        reject(err)
    }
})

// Execute API key prompt with native macOS dialog (without System Events permissions)
const set_api_key = async command => new Promise((resolve, reject) => {
    try {
        log(`Executing API key prompt via AppleScript: ${command}`)
        
        // Create AppleScript for a native macOS dialog without System Events
        const appleScript = `
            display dialog "Paste your CO2signal API key below:" default answer "1xYYY1xXXX1XXXxXXYyYYxXXyXyyyXXX" with title "Venti Setup" buttons {"Exit", "Submit"} default button "Submit"
            set theResult to the result
            if button returned of theResult is "Submit" then
                set apiKey to text returned of theResult
                return apiKey
            else
                return "CANCELED"
            end if
        `
        
        exec(`osascript -e '${appleScript}'`, shell_options, (error, stdout, stderr) => {
            if (error) {
                log('API key prompt error:', error)
                return reject(error)
            }
            
            // Clean up the returned key
            const apiKey = stdout.trim()
            
            if (apiKey === "CANCELED") {
                log('User cancelled API key input')
                app.exit()
                return resolve(null)
            }
            
            log('API key:', apiKey)
            exec_async(`${venti} set-api-key ${apiKey}`)
                .then(() => resolve(apiKey))
                .catch(err => reject(err))
        })
    } catch (err) {
        reject(err)
    }
})

/* ///////////////////////////////
// Battery cli functions
// /////////////////////////////*/
const enable_battery_limiter = async () => {

    try {
        // Start battery maintainer
        const status = await get_battery_status()
        await exec_async( `${ venti } maintain ${ status?.maintain_percentage || 80 }` )
        log( `enable_battery_limiter exec complete` )
    } catch( e ) {
        log( 'Error enabling venti: ', e )
        alert( e.message )
    }

}

const disable_battery_limiter = async () => {

    try {
        await exec_async( `${ venti } maintain stop` )
    } catch( e ) {
        log( 'Error enabling venti: ', e )
        alert( e.message )
    }

}

const update_or_install_venti = async () => {

    try {

        // Check for network
        const online = await Promise.race( [
            exec_async( `${ path_fix } curl icanhasip.com &> /dev/null` ).then( () => true ).catch( () => false ),
            exec_async( `${ path_fix } curl github.com &> /dev/null` ).then( () => true ).catch( () => false )
        ] )
        log( `Internet online: ${ online }` )

        // Check if xcode build tools are installed
        const xcode_installed = await exec_async( `${ path_fix } which git` ).catch( () => false )
        if( !xcode_installed ) {
            alert( `Venti needs Xcode developer tools to be installed, please accept the terms and conditions for installation` )
            await exec_async( `${ path_fix } xcode-select --install` )
            alert( `Please restart Venti after Xcode developer tools finish installing` )
            app.exit()
        }

        // Check if venti is installed
        const [
            venti_installed,
            smc_installed,
            charging_in_visudo,
            discharging_in_visudo,
            api_key
        ] = await Promise.all( [
            exec_async( `${ path_fix } which venti` ).catch( () => false ),
            exec_async( `${ path_fix } which smc` ).catch( () => false ),
            exec_async( `${ path_fix } sudo -n /usr/local/bin/smc -k CH0C -r` ).catch( () => false ),
            exec_async( `${ path_fix } sudo -n /usr/local/bin/smc -k CH0I -r` ).catch( () => false ),
            exec_async( `${ path_fix } cat ~/.venti/venti.conf | grep -o "APITOKEN=1xY"`).catch( () => false)
        ] )

        const visudo_complete = charging_in_visudo && discharging_in_visudo
        const is_installed = venti_installed && smc_installed 
        const api_key_complete = !api_key
        log( 'Is installed? ', is_installed )
        log( 'API key configed? ', api_key_complete )

        // Kill running instances of venti
        const processes = await exec_async( `ps aux | grep "/usr/local/bin/venti " | wc -l | grep -Eo "\\d*"` )
        log( `Found ${ `${ processes }`.replace( /\n/, '' ) } venti related processed to kill` )
        if( is_installed ) await exec_async( `${ venti } maintain stop` )
        await exec_async( `pkill -f "/usr/local/bin/venti.*"` ).catch( e => log( `Error killing existing venti processes, usually means no running processes` ) )

        // If installed, update
        if( is_installed && visudo_complete ) {
            if( !online ) return log( `Skipping venti update because we are offline` )
            log( `Updating venti...` )
            const result = await exec_async( `${ venti } update silent` )
            log( `Update result: `, result )
        }

        // If not installed, run install script
        if( !is_installed || !visudo_complete ) {
            log( `Installing venti for ${ USER }...` )
            if( !online ) return alert( `Venti needs an internet connection to download the latest version, please connect to the internet and open the app again.` )
            await alert( `Welcome to Venti. The app needs to install/update some components, so it will ask for your password. This should only be needed once.` )
            const result = await exec_sudo_async( `curl -s https://raw.githubusercontent.com/adamlechowicz/venti/main/setup.sh | zsh -s -- $USER` )
            log( `Install result: `, result )
            // await alert( `Venti needs a (free) CO2signal API key to reliably fetch carbon intensity values. You can get one at https://www.co2signal.com.`)
            // const result2 = await set_api_key(`api-key`)
            // log( `API key result: `, result2 )
            // if (!result2){
            //     app.exit()
            // }
            await alert( `Venti background components installed successfully. The app will now restart. You can find the Venti icon in the top right of your menu bar.` )
            app.relaunch()
            app.exit()
        }

        // If api key not configured
        if( !api_key_complete ) {
            await alert( `Venti needs a (free) CO2signal API key to reliably fetch carbon intensity values. You can get one at https://www.co2signal.com.`)
            const result2 = await set_api_key(`api-key`)
            log( `API key result: `, result2 )
            await alert( `API key set successfully. The app will now restart. You can find the Venti icon in the top right of your menu bar.` )
            app.relaunch()
            app.exit()
        }


    } catch( e ) {
        log( `Update/install error: `, e )
        alert( `Error installing Venti: ${ e.message }` )
    }

}


const is_limiter_enabled = async () => {

    try {
        const message = await exec_async( `${ venti } status` )
        log( `Limiter status message: `, message )
        return message.includes( 'being maintained at' )
    } catch( e ) {
        log( `Error getting venti status: `, e )
        alert( `Venti error: ${ e.message }` )
    }

}

const get_battery_status = async () => {

    try {
        const message = await exec_async( `${ venti } status_csv` )
        let [ percentage, remaining, charging, discharging, maintain_percentage, carbon ] = message.split( ',' )
        maintain_percentage = maintain_percentage.trim()
        maintain_percentage = maintain_percentage.length ? maintain_percentage : undefined
        charging = charging == 'enabled'
        discharging = discharging == 'discharging'
        remaining = remaining.match( /\d{1,2}:\d{1,2}/ ) ? remaining : 'unknown'
        
        let battery_state = `${ percentage }% (${ remaining } remaining)`
        if(charging){
            battery_state = `${ percentage }% (${ remaining } until fully charged)`
        }
        if(remaining === 'unknown'){
            battery_state = `${ percentage }% (adapter attached)`
        }
        let daemon_state = ``
        if( discharging ) daemon_state += `forcing discharge to ${ maintain_percentage || 80 }%`
        else daemon_state += `SMC charging ${ charging ? 'enabled' : 'disabled' }`

        carbon_intensity = `${ carbon } gCO2eq/kWh`

        return [ battery_state, daemon_state, maintain_percentage, carbon_intensity ]

    } catch( e ) {
        log( `Error getting venti status: `, e )
        alert( `Venti error: ${ e.message }` )
    }

}

module.exports = {
    enable_battery_limiter,
    disable_battery_limiter,
    update_or_install_venti,
    is_limiter_enabled,
    get_battery_status
}