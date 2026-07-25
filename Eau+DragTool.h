#import "Eau.h"

@interface Eau (DragTool)
- (void)enableDragMode;
- (void)disableDragMode;
- (BOOL)isDragModeEnabled;
- (bycopy NSString *)dragDeltaFilePath;
@end
