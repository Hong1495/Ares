import Foundation
import SubscriptionKit

actor RouteSnapshotService {
    private var database: RouteIPDatabase?
    private var databaseStamp = ""
    private var locationCache: [String: RouteLocation] = [:]
    private var attempted = Set<String>()
    private var countries: [String: RouteLocation] = [:]
    private var profileStamp = ""
    private var nodes: [String: RouteSnapshot.Node] = [:]
    // Freeze configuration-derived metadata per observed connection. Profile switches
    // cannot relabel a connection using a different server with the same node name.
    private var frozenNodes: [String: [String: RouteSnapshot.Node]] = [:]
    private var generation: UUID?

    func snapshot(inputs: [RouteSnapshot.Input], configURL: URL?, generation: UUID) async -> RouteSnapshot {
        if self.generation != generation { frozenNodes.removeAll(); self.generation = generation }
        loadDatabase()
        loadNodes(configURL)
        let active = Set(inputs.map(\.id))
        frozenNodes = frozenNodes.filter { active.contains($0.key) }
        var seen = Set<String>()
        // Group by frozen metadata as well, so a profile revision never merges different endpoints.
        var merged: [String: ObservedRoute] = [:]
        for input in inputs where seen.insert(input.id).inserted {
            if frozenNodes[input.id] == nil {
                var selected: [String: RouteSnapshot.Node] = [:]
                for name in input.chains { selected[name] = nodes[name] }
                frozenNodes[input.id] = selected
            }
            let metadata = frozenNodes[input.id] ?? [:]
            let addresses = [input.destinationIP] + metadata.values.map(\.server)
            var locations: [String: RouteLocation] = [:]
            for address in addresses { if let location = locate(address) { locations[address] = location } }
            guard let route = RouteSnapshot.build(inputs: [input], nodes: metadata, locations: locations).routes.first else { continue }
            let endpointData = (try? JSONEncoder().encode(route.endpoints.map { [$0.name, $0.address, $0.kind, $0.evidence] })).flatMap { String(data:$0,encoding:.utf8) } ?? ""
            let key = route.id + endpointData
            if var old = merged[key] { old.connections += 1; old.upload += route.upload; old.download += route.download; merged[key] = old }
            else {
                merged[key] = ObservedRoute(id:key, application:route.application, host:route.host, rule:route.rule, chain:route.chain,
                    endpoints:route.endpoints, connections:1, upload:route.upload, download:route.download)
            }
        }
        let result = merged.values.sorted { $0.application == $1.application ? $0.id < $1.id : $0.application < $1.application }
        return RouteSnapshot(routes: result)
    }
    private func loadNodes(_ url: URL?) {
        guard let url else { nodes = [:]; profileStamp = ""; return }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let stamp = "\(url.path)|\(date)"
        guard stamp != profileStamp else { return }
        profileStamp = stamp
        nodes = [:]
        guard let text = try? String(contentsOf: url, encoding:.utf8), let parsed = try? RouteNodeMetadata.parse(text) else { return }
        for node in parsed { nodes[node.name] = .init(name:node.name,server:node.server,type:node.type,dialer:node.dialer) }
    }
    private func loadDatabase() {
        if countries.isEmpty, let url = Bundle.main.url(forResource:"routing-countries",withExtension:"json"),
           let data = try? Data(contentsOf:url), let decoded = try? JSONDecoder().decode([String:RouteLocation].self,from:data) { countries = decoded }
        let support = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Ares")
        let paths = ["GeoLite2-City.mmdb", "clash_user/GeoLite2-City.mmdb", "clash_user/country.mmdb", "clash_user/Country.mmdb", "clash_user/geoip.metadb", "clash_root/country.mmdb", "clash_root/Country.mmdb", "clash_root/geoip.metadb", "clash/Country.mmdb"]
        let candidates = paths.map { support.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath:$0.path) }
        let stamp = candidates.map { url in
            let values = try? url.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
            return "\(url.path)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)"
        }.joined(separator:";")
        guard stamp != databaseStamp else { return }
        databaseStamp = stamp
        database = candidates.lazy.compactMap { try? RouteIPDatabase(url:$0) }.first
        attempted.removeAll(); locationCache.removeAll()
    }
    private func locate(_ address: String) -> RouteLocation? {
        if let cached = locationCache[address] { return cached }
        guard attempted.insert(address).inserted else { return nil }
        guard let record = database?.lookup(address) else { return nil }
        var location: RouteLocation?
        if let info = record["location"] as? [String:Any], let lat = info["latitude"] as? Double, let lon = info["longitude"] as? Double,
           lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) {
            let city = ((record["city"] as? [String:Any])?["names"] as? [String:String])?["en"] ?? "IP location"
            location = RouteLocation(longitude:lon,latitude:lat,label:city,precision:"IP geolocation estimate")
        } else if let code = (record["country"] as? [String:Any])?["iso_code"] as? String { location = countries[code] }
        if let location { locationCache[address] = location }
        // Bound cache memory without affecting the connection snapshot itself.
        if attempted.count > 50000 { attempted.removeAll(); locationCache.removeAll() }
        return location
    }
}
