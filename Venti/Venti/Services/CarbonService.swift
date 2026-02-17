import Foundation
import os

enum CarbonService {
    private static let logger = Logger.carbon

    // MARK: - Electricity Maps API response
    private struct CO2Response: Decodable {
        let carbonIntensity: Int?
        let zone: String?
    }

    // MARK: - IP Geolocation response
    private struct GeoResponse: Decodable {
        let lat: Double?
        let lon: Double?
    }

    /// Fetch current carbon intensity. Returns offline reading (intensity 0) on failure.
    static func fetchCarbonIntensity(apiToken: String, fixedRegion: String?) async -> CarbonReading {
        guard !apiToken.isEmpty, apiToken != Constants.placeholderAPIKey else {
            logger.warning("No valid API token configured")
            return cachedOrOffline()
        }

        let locationQuery: String
        if let region = fixedRegion, !region.isEmpty, region != "False" {
            locationQuery = "zone=\(region)"
        } else {
            locationQuery = await getLocationQuery()
        }

        guard !locationQuery.isEmpty else {
            logger.warning("Could not determine location, using cached/offline")
            return cachedOrOffline()
        }

        guard let url = URL(string: "\(Constants.electricityMapsBaseURL)?\(locationQuery)") else {
            return cachedOrOffline()
        }

        var request = URLRequest(url: url)
        request.setValue(apiToken, forHTTPHeaderField: "auth-token")
        request.timeoutInterval = 15

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(CO2Response.self, from: data)

            if let intensity = response.carbonIntensity {
                let region = response.zone ?? Constants.defaultRegion
                let reading = CarbonReading(
                    intensity: intensity,
                    region: region,
                    timestamp: .now
                )
                cacheReading(reading)
                logger.info("Carbon intensity: \(reading.intensity) gCO2eq/kWh, region: \(reading.region)")
                return reading
            }
        } catch {
            logger.error("Electricity Maps API error: \(error.localizedDescription)")
        }

        return cachedOrOffline()
    }

    // MARK: - Geolocation

    private static func getLocationQuery() async -> String {
        // ip-api.com geolocates the caller directly — no need for a separate IP lookup.
        // The fields parameter limits the response to just lat/lon.
        guard let geoURL = URL(string: "\(Constants.geoLookupURL)/?fields=lat,lon") else { return "" }
        do {
            var geoRequest = URLRequest(url: geoURL)
            geoRequest.timeoutInterval = 10
            let (geoData, _) = try await URLSession.shared.data(for: geoRequest)
            let geo = try JSONDecoder().decode(GeoResponse.self, from: geoData)

            if let lat = geo.lat, let lon = geo.lon {
                return "lat=\(lat)&lon=\(lon)"
            }
        } catch {
            logger.error("Geolocation error: \(error.localizedDescription)")
        }
        return ""
    }

    // MARK: - Cache

    private static func cacheReading(_ reading: CarbonReading) {
        UserDefaults.standard.set(reading.intensity, forKey: Constants.Defaults.lastCarbonIntensity)
        UserDefaults.standard.set(reading.region, forKey: Constants.Defaults.lastCarbonRegion)
    }

    private static func cachedOrOffline() -> CarbonReading {
        let intensity = UserDefaults.standard.integer(forKey: Constants.Defaults.lastCarbonIntensity)
        let region = UserDefaults.standard.string(forKey: Constants.Defaults.lastCarbonRegion) ?? Constants.defaultRegion
        if intensity > 0 {
            logger.info("Using cached carbon reading: \(intensity) gCO2eq/kWh")
            return CarbonReading(intensity: intensity, region: region, timestamp: .now)
        }
        return .offline
    }
}
