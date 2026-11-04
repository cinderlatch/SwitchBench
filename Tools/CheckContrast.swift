import AppKit
var results:[[String:Any]]=[]
func luminance(_ values:[Double])->Double {
    let linear=values.map {$0<=0.04045 ? $0/12.92 : pow(($0+0.055)/1.055,2.4)}
    return linear[0]*0.2126+linear[1]*0.7152+linear[2]*0.0722
}
for name in [NSAppearance.Name.aqua,.darkAqua,.accessibilityHighContrastAqua,.accessibilityHighContrastDarkAqua] {
    NSAppearance(named:name)!.performAsCurrentDrawingAppearance {
        for (label,background) in [("window",NSColor.windowBackgroundColor),("card",NSColor.controlBackgroundColor)] {
            let bg=background.usingColorSpace(.sRGB)!,fg=NSColor.labelColor.usingColorSpace(.sRGB)!
            let backdrop=[bg.redComponent,bg.greenComponent,bg.blueComponent].map(Double.init),text=[fg.redComponent,fg.greenComponent,fg.blueComponent].map(Double.init)
            for opacity in [1.0,0.78] {
                let alpha=Double(fg.alphaComponent)*opacity,rendered=zip(text,backdrop).map {$0*alpha+$1*(1-alpha)}
                let a=luminance(rendered),b=luminance(backdrop),ratio=(max(a,b)+0.05)/(min(a,b)+0.05)
                results.append(["appearance":name.rawValue,"background":label,"textOpacity":opacity,"contrast":ratio,"passes4_5":ratio>=4.5])
                precondition(ratio>=4.5,"Text contrast below target")
            }
        }
    }
}
let data=try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
print("PASS: all 16 primary/supporting-text contrast combinations exceed 4.5:1 in standard and high-contrast light/dark appearances")
