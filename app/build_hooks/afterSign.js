/* ///////////////////////////////
// Notarization
// See https://kilianvalkhof.com/2019/electron/notarizing-your-electron-application/
// /////////////////////////////*/
require('dotenv').config()
const { notarize } = require('electron-notarize')
const { spawn } = require('child_process')
const log = ( ...messages ) => console.log( ...messages )

exports.default = async function notarizing(context) {
    
    log( '\n\n🪝 afterSign hook triggered: ' )
    const { appOutDir } = context 
    const { APPLEID, APPLEIDPASS, TEAMID } = process.env
    const appName = context.packager.appInfo.productFilename

    try {
        await notarize( {
            appBundleId: 'com.adamlechowicz.venti',
            tool: "notarytool",
            appPath: `${appOutDir}/${appName}.app`,
            appleId: APPLEID,
            appleIdPassword: APPLEIDPASS,
            teamId: TEAMID
        } )
    } catch (error) {
        if (error.message?.includes('Failed to staple')) {
          spawn(`xcrun`, ['stapler', 'staple', `${appOutDir}/${appName}.app`])
        } else {
          throw error
        }
    }
}