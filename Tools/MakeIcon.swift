import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
 color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
for size in [16,32,64,128,256,512,1024] {
 let image = NSImage(size: NSSize(width:size,height:size)); image.lockFocus()
 let scale = CGFloat(size)/1024
 NSAffineTransform(transform: AffineTransform(scale:scale)).concat()
 let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.24); shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width:0,height:-12)
 NSGraphicsContext.saveGraphicsState(); shadow.set()
 rounded(NSRect(x:76,y:76,width:872,height:872),190,NSColor(red:0.035,green:0.29,blue:0.30,alpha:1))
 NSGraphicsContext.restoreGraphicsState()
 let gradient = NSGradient(starting:NSColor(red:0.13,green:0.66,blue:0.61,alpha:1),ending:NSColor(red:0.035,green:0.34,blue:0.36,alpha:1))!
 gradient.draw(in:NSBezierPath(roundedRect:NSRect(x:76,y:76,width:872,height:872),xRadius:190,yRadius:190),angle:-55)
 rounded(NSRect(x:270,y:280,width:360,height:490),65,NSColor.white.withAlphaComponent(0.25))
 rounded(NSRect(x:355,y:210,width:360,height:490),65,NSColor(red:0.97,green:0.98,blue:0.92,alpha:1))
 rounded(NSRect(x:425,y:540,width:220,height:88),18,NSColor(red:0.06,green:0.38,blue:0.39,alpha:1))
 // A tools symbol represents the whole workbench at Dock sizes.
 if let tools = NSImage(systemSymbolName:"wrench.and.screwdriver.fill",accessibilityDescription:nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[NSColor(red:0.06,green:0.38,blue:0.39,alpha:1)])) {
     tools.draw(in:NSRect(x:425,y:285,width:220,height:220))
 }
 image.unlockFocus()
 let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
 try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("icon-\(size).png"))
}

// ICNS supports PNG representations directly. Build the container without relying
// on iconutil, which is unavailable in some restricted build environments.
var chunks = Data()
func bigEndian(_ value: UInt32) -> Data {
    var n = value.bigEndian
    return withUnsafeBytes(of: &n) { Data($0) }
}
for (size, type) in [(16,"icp4"),(32,"icp5"),(64,"icp6"),(128,"ic07"),(256,"ic08"),(512,"ic09"),(1024,"ic10")] {
    let png = try Data(contentsOf: directory.appendingPathComponent("icon-\(size).png"))
    chunks.append(Data(type.utf8)); chunks.append(bigEndian(UInt32(png.count + 8))); chunks.append(png)
}
var icns = Data("icns".utf8); icns.append(bigEndian(UInt32(chunks.count + 8))); icns.append(chunks)
try icns.write(to: directory.appendingPathComponent("AppIcon.icns"))
guard let decoded = NSImage(data: icns), decoded.isValid else { fatalError("Invalid application icon") }
