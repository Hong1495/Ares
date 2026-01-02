import AppKit

// Colors (Japanese Traditional)
// Active (Green)
let activeLightColor = NSColor(srgbRed: 0.658, green: 0.847, blue: 0.725, alpha: 1.0) // #A8D8B9 (Byakuroku) - For Dark Mode/Bar
let activeDarkColor = NSColor(srgbRed: 0.0, green: 0.345, blue: 0.192, alpha: 1.0)    // #005831 (Tokiwa-iro) - For Light Mode/Bar

// Inactive (Grey)
let inactiveLightColor = NSColor(srgbRed: 0.902, green: 0.918, blue: 0.890, alpha: 1.0) // #E6EAE3 (Geppaku) - For Dark Mode/Bar
let inactiveDarkColor = NSColor(srgbRed: 0.192, green: 0.192, blue: 0.192, alpha: 1.0)  // #313131 (Sumi-iro) - For Light Mode/Bar

func processImage(inputPath: String, active: Bool) {
    let fileURL = URL(fileURLWithPath: inputPath)
    guard let data = try? Data(contentsOf: fileURL),
          let originalRep = NSBitmapImageRep(data: data) else {
        print("Failed to load: \(inputPath)")
        return
    }
    
    // Determine colors
    let colorForDarkBar = active ? activeLightColor : inactiveLightColor // Light Icon
    let colorForLightBar = active ? activeDarkColor : inactiveDarkColor // Dark Icon
    
    // Determine output paths
    // "menu_xx@2x.png" -> "menu_xx_dark@2x.png" (Light Color)
    // "menu_xx@2x.png" -> "menu_xx_light@2x.png" (Dark Color)
    // Note: "_dark" suffix here means "For Dark Apperance", so it's the Light Color Icon.
    // Note: "_light" suffix here means "For Light Apperance", so it's the Dark Color Icon.
    
    let pathExtension = fileURL.pathExtension
    let pathNoExt = fileURL.deletingPathExtension().path
    
    let pathForDarkApp = pathNoExt + "_dark." + pathExtension
    let pathForLightApp = pathNoExt + "_light." + pathExtension
    
    saveTinted(rep: originalRep, color: colorForDarkBar, saveTo: pathForDarkApp)
    saveTinted(rep: originalRep, color: colorForLightBar, saveTo: pathForLightApp)
}

func saveTinted(rep: NSBitmapImageRep, color: NSColor, saveTo: String) {
    let size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    // Create new context
    guard let newRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: rep.pixelsWide,
        pixelsHigh: rep.pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return }
    
    newRep.size = size
    
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: newRep)
    NSGraphicsContext.current = context
    
    // 1. Fill with Color (The Tint)
    color.set()
    let rect = NSRect(origin: .zero, size: size)
    rect.fill()
    
    // 2. Draw Source Image using DestinationIn (Result = DestColor * SourceAlpha)
    // We need an NSImage to draw
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
    
    NSGraphicsContext.restoreGraphicsState()
    
    if let pngData = newRep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: saveTo))
        print("Saved: \(saveTo)")
    }
}

let basePath = "/Users/sweethoney/Downloads/Ares/Ares/Assets.xcassets"
let menus = ["Ares_Menu_00", "Ares_Menu_01", "Ares_Menu_10", "Ares_Menu_11"]

for menu in menus {
    let suffix = menu.components(separatedBy: "_").last!
    let isActive = (suffix != "00")
    
    let dir = "\(basePath)/\(menu).imageset"
    let fileName = "menu_\(suffix)"
    
    // Process 1x
    // processImage(inputPath: "\(dir)/\(fileName).png", active: isActive) 
    // Wait, original might not look good scaled? Assuming 1x exists.
    // Based on previous ls, 1x AND 2x exist.
    processImage(inputPath: "\(dir)/\(fileName).png", active: isActive)
    processImage(inputPath: "\(dir)/\(fileName)@2x.png", active: isActive)
}
