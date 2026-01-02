import AppKit

func printColor(path: String) {
    let url = URL(fileURLWithPath: path)
    guard let rep = NSBitmapImageRep(data: try! Data(contentsOf: url)) else {
        print("\(path): Fail load")
        return
    }
    
    // Check for first non-transparent pixel
    var found = false
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                if let srgb = color.usingColorSpace(.sRGB) {
                     let r = Int(srgb.redComponent * 255)
                     let g = Int(srgb.greenComponent * 255)
                     let b = Int(srgb.blueComponent * 255)
                     print("\(url.lastPathComponent): R\(r) G\(g) B\(b) (found at \(x),\(y))")
                     found = true
                     break
                }
            }
        }
        if found { break }
    }
    if !found { print("\(url.lastPathComponent): Fully Transparent") }
}

let base = "/Users/sweethoney/Downloads/Ares/Ares/Assets.xcassets/Ares_Menu_01.imageset"
printColor(path: "\(base)/menu_01_light.png")
printColor(path: "\(base)/menu_01_dark.png")
