#import "Eau+DragTool.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// ── Overlay view: draws a 1px blue border around the dragged widget ──
@interface DTBorderView : NSView
@end

@implementation DTBorderView
- (void)drawRect:(NSRect)dirtyRect
{
  [NSBezierPath setDefaultLineWidth:1.0];
  [[NSColor blueColor] set];
  NSFrameRect(self.bounds);
}
- (NSView *)hitTest:(NSPoint)aPoint
{
  return nil;
}
@end

// ── Per-class original IMP storage ──────────────────────────────────
static struct OrigIMPs {
  Class cls;
  IMP mouseDown, mouseDragged, mouseUp;
} *s_origTable = NULL;
static int s_origCount = 0, s_origCap = 0;

static struct OrigIMPs *origForClass(Class c)
{
  for (int i = 0; i < s_origCount; i++)
    if (s_origTable[i].cls == c) return &s_origTable[i];
  return NULL;
}

static void saveOrig(Class c, SEL sel1, IMP imp1,
                     SEL sel2, IMP imp2,
                     SEL sel3, IMP imp3)
{
  if (origForClass(c)) return;
  if (s_origCount >= s_origCap) {
    s_origCap = s_origCap ? s_origCap * 2 : 128;
    s_origTable = realloc(s_origTable, s_origCap * sizeof(struct OrigIMPs));
  }
  int i = s_origCount++;
  s_origTable[i].cls = c;
  Method m;
  m = class_getInstanceMethod(c, sel1);
  s_origTable[i].mouseDown    = m ? method_getImplementation(m) : imp1;
  m = class_getInstanceMethod(c, sel2);
  s_origTable[i].mouseDragged = m ? method_getImplementation(m) : imp2;
  m = class_getInstanceMethod(c, sel3);
  s_origTable[i].mouseUp      = m ? method_getImplementation(m) : imp3;
}

// ── Forward declarations for swizzled functions ─────────────────────
static void dt_mouseDown(id self, SEL _cmd, id ev);
static void dt_mouseDragged(id self, SEL _cmd, id ev);
static void dt_mouseUp(id self, SEL _cmd, id ev);

// ── Global drag-mode state ─────────────────────────────────────────
static BOOL  s_dragEnabled = NO;
static int   s_deltaFD     = -1;
static char  s_deltaPath[256];

// ── Associated object key for origin storage ───────────────────────
static char s_originKey;
static char s_borderKey;

// ── Delta file management ──────────────────────────────────────────
static void openDeltas(void)
{
  if (s_deltaFD >= 0) close(s_deltaFD);
  snprintf(s_deltaPath, sizeof(s_deltaPath),
           "/tmp/dragtool_deltas_%d.txt", getpid());
  s_deltaFD = open(s_deltaPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
}

static void closeDeltas(void)
{
  if (s_deltaFD >= 0) { close(s_deltaFD); s_deltaFD = -1; }
}

// ── Helpers ────────────────────────────────────────────────────────
static NSRect frameOf(id view)
{
  return [(NSView *)view frame];
}

static void setFrameOriginOf(id view, NSPoint origin)
{
  [(NSView *)view setFrameOrigin:origin];
}

static DTBorderView *borderFor(id view)
{
  return (DTBorderView *)objc_getAssociatedObject(view, &s_borderKey);
}

static void setBorderFor(id view, DTBorderView *bv)
{
  objc_setAssociatedObject(view, &s_borderKey, (id)bv,
    OBJC_ASSOCIATION_RETAIN);
}

// ── Swizzled mouse handlers ────────────────────────────────────────
static void dt_mouseDown(id self, SEL _cmd, id ev)
{
  struct OrigIMPs *o = origForClass(object_getClass(self));
  if (!s_dragEnabled) {
    if (o && o->mouseDown)
      ((void(*)(id, SEL, id))o->mouseDown)(self, _cmd, ev);
    return;
  }

  // Store start position
  NSValue *originVal = [NSValue valueWithPoint:frameOf(self).origin];
  objc_setAssociatedObject(self, &s_originKey, originVal,
    OBJC_ASSOCIATION_RETAIN);

  // Create and add blue border overlay
  DTBorderView *bv = [[DTBorderView alloc] initWithFrame:frameOf(self)];
  [bv setAutoresizingMask:NSViewNotSizable];
  [[self superview] addSubview:bv positioned:NSWindowAbove relativeTo:self];
  setBorderFor(self, bv);
}

static void dt_mouseDragged(id self, SEL _cmd, id ev)
{
  struct OrigIMPs *o = origForClass(object_getClass(self));
  if (!s_dragEnabled) {
    if (o && o->mouseDragged)
      ((void(*)(id, SEL, id))o->mouseDragged)(self, _cmd, ev);
    return;
  }

  NSPoint origin = frameOf(self).origin;
  origin.x += [ev deltaX];
  origin.y -= [ev deltaY];
  setFrameOriginOf(self, origin);

  // Move border to match
  DTBorderView *bv = borderFor(self);
  if (bv) [bv setFrameOrigin:origin];
}

static void dt_mouseUp(id self, SEL _cmd, id ev)
{
  struct OrigIMPs *o = origForClass(object_getClass(self));
  if (!s_dragEnabled) {
    if (o && o->mouseUp)
      ((void(*)(id, SEL, id))o->mouseUp)(self, _cmd, ev);
    return;
  }

  // Remove border overlay
  DTBorderView *bv = borderFor(self);
  if (bv) {
    [bv removeFromSuperview];
    setBorderFor(self, nil);
  }

  // Calculate and write delta
  NSValue *originVal = objc_getAssociatedObject(self, &s_originKey);
  if (originVal && s_deltaFD >= 0) {
    NSPoint start = [originVal pointValue];
    NSPoint end   = frameOf(self).origin;
    CGFloat dx = end.x - start.x;
    CGFloat dy = end.y - start.y;
    if (fabs(dx) > 0.5 || fabs(dy) > 0.5) {
      NSString *title = @"";
      if ([self respondsToSelector:@selector(title)])
        title = [self performSelector:@selector(title)] ?: @"";
      else if ([self respondsToSelector:@selector(stringValue)])
        title = [self performSelector:@selector(stringValue)] ?: @"";

      NSString *className = NSStringFromClass(object_getClass(self));
      NSString *line = [NSString stringWithFormat:
        @"move: %@ \"%@\" dx=(%.0f) dy=(%.0f) object=%p\n",
        className, title, dx, dy, self];
      const char *utf8 = [line UTF8String];
      if (utf8) write(s_deltaFD, utf8, strlen(utf8));
    }
  }

  objc_setAssociatedObject(self, &s_originKey, nil,
    OBJC_ASSOCIATION_RETAIN);

  // Forward to original
  if (o && o->mouseUp)
    ((void(*)(id, SEL, id))o->mouseUp)(self, _cmd, ev);
}

// ── Swizzle all NSView subclasses ──────────────────────────────────
static BOOL s_swizzled = NO;

static void swizzleClass(Class c)
{
  SEL sels[3] = {
    @selector(mouseDown:),
    @selector(mouseDragged:),
    @selector(mouseUp:)
  };
  IMP newImps[3] = {
    (IMP)dt_mouseDown,
    (IMP)dt_mouseDragged,
    (IMP)dt_mouseUp
  };

  saveOrig(c, sels[0], newImps[0], sels[1], newImps[1], sels[2], newImps[2]);
  for (int i = 0; i < 3; i++) {
    Method m = class_getInstanceMethod(c, sels[i]);
    if (m)
      method_setImplementation(m, newImps[i]);
    else
      class_addMethod(c, sels[i], newImps[i], "v@:@");
  }
}

static void swizzleAllNSViews(void)
{
  if (s_swizzled) return;

  int cnt = objc_getClassList(NULL, 0);
  Class *buf = (Class *)malloc(sizeof(Class) * cnt);
  cnt = objc_getClassList(buf, cnt);

  for (int i = 0; i < cnt; i++) {
    Class c = buf[i];
    // Check if NSView subclass
    for (Class s = c; s; s = class_getSuperclass(s)) {
      if (s == [NSView class]) {
        swizzleClass(c);
        break;
      }
    }
  }
  free(buf);
  s_swizzled = YES;
}

// ── DragTool implementation (category on Eau) ──────────────────────
@implementation Eau (DragTool)

- (void)enableDragMode
{
  swizzleAllNSViews();
  openDeltas();
  s_dragEnabled = YES;
  NSLog(@"DragTool: drag mode ENABLED (deltas -> %s)", s_deltaPath);
}

- (void)disableDragMode
{
  s_dragEnabled = NO;
  closeDeltas();
  NSLog(@"DragTool: drag mode DISABLED");
}

- (BOOL)isDragModeEnabled
{
  return s_dragEnabled;
}

- (bycopy NSString *)dragDeltaFilePath
{
  return [NSString stringWithUTF8String:s_deltaPath];
}

@end
