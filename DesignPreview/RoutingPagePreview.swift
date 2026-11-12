import SwiftUI

@main struct RoutingPagePreview: App {
    var body: some Scene {
        WindowGroup("Ares · Routing Preview · Sample Data") { Preview().frame(minWidth:850,minHeight:620) }
            .defaultSize(width:1100,height:760)
    }
    struct Preview: View {
        @State private var dark=false
        @State private var empty=false
        @State private var unknown=false
        var body: some View {
            RoutingPresentation(snapshot:empty ? RouteSnapshot() : sample,status:"")
                .preferredColorScheme(dark ? .dark : .light)
                .toolbar {
                    ToolbarItem(placement:.primaryAction) {
                        HStack {
                            Toggle("Sample: unknown",isOn:$unknown)
                            Toggle("Empty",isOn:$empty)
                            Toggle("Dark",isOn:$dark)
                        }.toggleStyle(.checkbox).font(.system(size:11))
                    }
                }
        }
        var sample: RouteSnapshot {
            var inputs: [RouteSnapshot.Input] = []
            for i in 0..<160 {
                inputs.append(RouteSnapshot.Input(id:"fixture-\(i)",application:i%2==0 ? "Safari" : "Terminal",host:i%3==0 ? "api.example.test" : "cdn.example.test",
                    destinationIP:i%3==0 ? "81.2.69.160" : "89.160.20.128",rule:"RuleSet",chains:["Tokyo sample","Auto"],upload:Int64(i*100),download:Int64(i*500)))
            }
            let locations:[String:RouteLocation] = unknown ? [:] : [
                "2001:218::":.init(longitude:139.75,latitude:35.68,label:"Tokyo",precision:"Sample IP location"),
                "81.2.69.160":.init(longitude:-0.09,latitude:51.51,label:"London",precision:"Sample IP location"),
                "89.160.20.128":.init(longitude:15.61,latitude:58.41,label:"Sweden",precision:"Country estimate")]
            return RouteSnapshot.build(inputs:inputs,nodes:["Tokyo sample":.init(name:"Tokyo sample",server:"2001:218::",type:"vless",dialer:nil)],locations:locations)
        }
    }
}
