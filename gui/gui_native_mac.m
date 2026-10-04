// macOS: NSWindowの内側の大きさを変える(論理座標)
#import <Cocoa/Cocoa.h>

void bubiz_native_resize(void *window, int w, int h)
{
	NSWindow *win = (__bridge NSWindow *)window;
	[win setContentSize:NSMakeSize(w, h)];
}
