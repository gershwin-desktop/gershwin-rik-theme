/*
 * NSButtonCell+Eau.m
 * Eau Theme - Button Cell Enhancements
 *
 * This file uses the method swizzling pattern for NSButtonCell to:
 * 1. Intercept common_ret/common_retH images and hide them
 * 2. Automatically set buttons with these images as default buttons
 * 3. Enable pulsing animation for default buttons
 * 4. Make default buttons appear selected with highlighted border
 * 5. Ensure crash-safe operation even when windows/buttons cannot be found
 * While 2, 3, and 4 could be done by the application,
 * most applications will not do this, so we handle it here. 
 */

#import "NSCell+Eau.h"
#import "NSButtonCell+Eau.h"
#import "Eau+Button.h"
#import "AppearanceMetrics.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

// Prevent the specific "return" images from ever being drawn by intercepting common draw methods.
@interface NSImage(EauSuppressReturnImageDraw)
@end

@implementation NSImage(EauSuppressReturnImageDraw)

+ (void)load
{
  // Grand Central Dispatch may not be available in all build environments; use a simple synchronized guard.
  static BOOL EAU_swizzled = NO;
  @synchronized([NSImage class]) {
    if (EAU_swizzled) return;
    EAU_swizzled = YES;

    Class cls = [self class];
    Method orig, swiz;

    orig = class_getInstanceMethod(cls, @selector(drawAtPoint:));
    swiz = class_getInstanceMethod(cls, @selector(EAU_drawAtPoint:));
    if (orig && swiz) method_exchangeImplementations(orig, swiz);

    orig = class_getInstanceMethod(cls, @selector(drawInRect:));
    swiz = class_getInstanceMethod(cls, @selector(EAU_drawInRect:));
    if (orig && swiz) method_exchangeImplementations(orig, swiz);

    orig = class_getInstanceMethod(cls, @selector(drawInRect:fromRect:operation:fraction:));
    swiz = class_getInstanceMethod(cls, @selector(EAU_drawInRect:fromRect:operation:fraction:));
    if (orig && swiz) method_exchangeImplementations(orig, swiz);

    orig = class_getInstanceMethod(cls, @selector(drawInRect:fromRect:operation:fraction:respectFlipped:hints:));
    swiz = class_getInstanceMethod(cls, @selector(EAU_drawInRect:fromRect:operation:fraction:respectFlipped:hints:));
    if (orig && swiz) method_exchangeImplementations(orig, swiz);
  }
}

- (BOOL)EAU_isReturnImage
{
  NSString *name = [self name];
  if (!name) return NO;
  NSString *base = [name stringByDeletingPathExtension];
  return [base isEqualToString:@"common_ret"] || [base isEqualToString:@"common_retH"];
}

- (void)EAU_drawAtPoint:(NSPoint)point
{
  if ([self EAU_isReturnImage]) {
    NSDebugLog(@"NSImage: Suppressing drawAtPoint for %@", [self name]);
    return;
  }
  [self EAU_drawAtPoint:point];
}

- (void)EAU_drawInRect:(NSRect)rect
{
  if ([self EAU_isReturnImage]) {
    NSDebugLog(@"NSImage: Suppressing drawInRect for %@", [self name]);
    return;
  }
  [self EAU_drawInRect:rect];
}

- (void)EAU_drawInRect:(NSRect)rect fromRect:(NSRect)srcRect operation:(NSCompositingOperation)op fraction:(CGFloat)delta
{
  if ([self EAU_isReturnImage]) {
    NSDebugLog(@"NSImage: Suppressing drawInRect:fromRect:operation:fraction: for %@", [self name]);
    return;
  }
  [self EAU_drawInRect:rect fromRect:srcRect operation:op fraction:delta];
}

- (void)EAU_drawInRect:(NSRect)rect fromRect:(NSRect)srcRect operation:(NSCompositingOperation)op fraction:(CGFloat)delta respectFlipped:(BOOL)respectFlipped hints:(NSDictionary *)hints
{
  if ([self EAU_isReturnImage]) {
    NSDebugLog(@"NSImage: Suppressing drawInRect:respectFlipped:hints: for %@", [self name]);
    return;
  }
  [self EAU_drawInRect:rect fromRect:srcRect operation:op fraction:delta respectFlipped:respectFlipped hints:hints];
}

@end

@implementation Eau(NSButtonCell)
// Override image method using GSTheme method swizzling pattern
- (NSImage *) _overrideNSButtonCellMethod_image
{
  NSButtonCell *xself = (NSButtonCell*) self;
  return [xself EAUimage];
}

// Override alternateImage method using GSTheme method swizzling pattern
- (NSImage *) _overrideNSButtonCellMethod_alternateImage
{
  NSButtonCell *xself = (NSButtonCell*) self;
  return [xself EAUalternateImage];
}
@end

@implementation NSButtonCell(EauTheme)

// Prevent infinite recursion during image processing
static NSMutableSet *processingCells = nil;
static NSMutableSet *defaultButtonSetCells = nil;
static NSMutableSet *returnImageCells = nil;

+ (void)load
{
  processingCells = [[NSMutableSet alloc] init];
  defaultButtonSetCells = [[NSMutableSet alloc] init];
  returnImageCells = [[NSMutableSet alloc] init];

  // Swizzle -drawInteriorWithFrame:inView: so we can ignore return images for
  // layout calculations (prevents title shifting when mouse is pressed).
  Class cls = [NSButtonCell class];
  Method orig = class_getInstanceMethod(cls, @selector(drawInteriorWithFrame:inView:));
  Method swiz = class_getInstanceMethod(cls, @selector(EAU_drawInteriorWithFrame:inView:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  // Swizzle -cellSize so buttons always request at least the minimum width
  // (METRICS_BUTTON_MIN_WIDTH), giving the pill shape enough horizontal room.
  orig = class_getInstanceMethod(cls, @selector(cellSize));
  swiz = class_getInstanceMethod(cls, @selector(EAU_cellSize));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);
}

// Helper methods to track processing state
- (BOOL) isProcessingReturnButton
{
  @synchronized(processingCells) {
    return [processingCells containsObject:[NSValue valueWithPointer:(__bridge const void *)(self)]];
  }
}

- (void) setIsProcessingReturnButton:(BOOL)processing
{
  @synchronized(processingCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:(__bridge const void *)(self)];
    if (processing) {
      [processingCells addObject:cellPtr];
    } else {
      [processingCells removeObject:cellPtr];
    }
  }
}

// Handle common_ret/common_retH images: hide them and enable button pulsing
- (NSImage *) EAUimage
{
  NSImage *originalImage = [super image];
  if (originalImage)
    {
      NSString *imageName = [originalImage name];
      NSString *baseName = imageName ? [imageName stringByDeletingPathExtension] : nil;
      
      if (baseName && ([baseName isEqualToString:@"common_ret"] || 
                       [baseName isEqualToString:@"common_retH"]))
        {
          // Remember that this cell is using the suppressed return image so
          // we can treat layout differently while it's highlighted.
          @synchronized(returnImageCells) {
            [returnImageCells addObject:[NSValue valueWithPointer:(__bridge const void *)(self)]];
          }

          // Prevent infinite loops
          if (![self isProcessingReturnButton]) {
            [self setIsProcessingReturnButton:YES];
            [self setIsDefaultButton:@YES];
            [self enablePulsing];
            [self setIsProcessingReturnButton:NO];
          }
          
          return nil; // Hide the image
        }
    }
  
  return originalImage;
}

// Intercept setImage to handle common_ret/common_retH images
- (void) setImage:(NSImage *)image
{
  if (image) {
    NSString *imageName = [image name];
    NSString *baseName = imageName ? [imageName stringByDeletingPathExtension] : nil;
    
    if (baseName && ([baseName isEqualToString:@"common_ret"] || 
                     [baseName isEqualToString:@"common_retH"])) {
      
      // Remember that this cell is using the suppressed return image so
      // we can treat layout differently while it's highlighted.
      @synchronized(returnImageCells) {
        [returnImageCells addObject:[NSValue valueWithPointer:(__bridge const void *)(self)]];
      }

      // Prevent infinite loops
      if (![self isProcessingReturnButton]) {
        [self setIsProcessingReturnButton:YES];
        [self setIsDefaultButton:@YES];
        // Keep the guard set ACROSS enablePulsing: it re-drives setKeyEquivalent:,
        // which routes through GSTheme back into setImage: (the return-arrow image).
        // Clearing the flag before enablePulsing left that re-entry unguarded and
        // produced an infinite setImage:/setKeyEquivalent: recursion (stack overflow).
        [self enablePulsing];
        [self setIsProcessingReturnButton:NO];
      }
      
      return; // Don't set the image
    }
  }
  
  [super setImage:image];
}

// Handle common_ret/common_retH alternate images
- (NSImage *) EAUalternateImage
{
  NSImage *originalImage = nil;

  if ([self respondsToSelector:@selector(alternateImage)]) {
    originalImage = ((NSButtonCell *)self).alternateImage;
  }

  if (originalImage)
    {
      NSString *imageName = [originalImage name];
      NSString *baseName = imageName ? [imageName stringByDeletingPathExtension] : nil;
      
      if (baseName && ([baseName isEqualToString:@"common_ret"] || 
                       [baseName isEqualToString:@"common_retH"]))
        {
          // Remember that this cell is using the suppressed return image so
          // we can treat layout differently while it's highlighted.
          @synchronized(returnImageCells) {
            [returnImageCells addObject:[NSValue valueWithPointer:(__bridge const void *)(self)]];
          }

          // Prevent infinite loops
          if (![self isProcessingReturnButton]) {
            [self setIsProcessingReturnButton:YES];
            [self setIsDefaultButton:@YES];
            [self enablePulsing];
            [self setIsProcessingReturnButton:NO];
          }
          
          return nil; // Hide the image
        }
    }
  
  return originalImage;
}

// Intercept setAlternateImage to handle common_ret/common_retH images
- (void) EAU_setAlternateImage:(NSImage *)alternateImage
{
  if (alternateImage) {
    NSString *imageName = [alternateImage name];
    NSString *baseName = imageName ? [imageName stringByDeletingPathExtension] : nil;
    
    if (baseName && ([baseName isEqualToString:@"common_ret"] || 
                     [baseName isEqualToString:@"common_retH"])) {
      // Remember that this cell is using the suppressed return image so
      // we can treat layout differently while it's highlighted.
      @synchronized(returnImageCells) {
        [returnImageCells addObject:[NSValue valueWithPointer:(__bridge const void *)(self)]];
      }

      // Prevent infinite loops
      if (![self isProcessingReturnButton]) {
        [self setIsProcessingReturnButton:YES];
        [self setIsDefaultButton:@YES];
        // Keep the guard set ACROSS enablePulsing: it re-drives setKeyEquivalent:,
        // which routes through GSTheme back into setImage: (the return-arrow image).
        // Clearing the flag before enablePulsing left that re-entry unguarded and
        // produced an infinite setImage:/setKeyEquivalent: recursion (stack overflow).
        [self enablePulsing];
        [self setIsProcessingReturnButton:NO];
      }
      
      return; // Don't set the image
    }
  }
  if ([self respondsToSelector:@selector(setAlternateImage:)]) {
    [(NSButtonCell *)self setAlternateImage:alternateImage];
  }
}

// Enable pulsing animation for default buttons and make them selected
- (void) enablePulsing
{
  NSDebugLog(@"NSButtonCell+Eau: enablePulsing called for button cell %p", self);
  
  // Prevent multiple enablePulsing calls for the same cell
  @synchronized(defaultButtonSetCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:(__bridge const void *)(self)];
    if ([defaultButtonSetCells containsObject:cellPtr]) {
      NSDebugLog(@"NSButtonCell+Eau: Button cell %p already enabled for pulsing, skipping", self);
      return;
    }
  }
  
  NSDebugLog(@"NSButtonCell+Eau: Setting button cell %p as default button", self);
  [self setIsDefaultButton:@YES];
  
  NSDebugLog(@"NSButtonCell+Eau: Making button cell %p selected and highlighted", self);
  [self safelyMakeButtonSelectedAndHighlighted];
  
  NSDebugLog(@"NSButtonCell+Eau: Starting strategy to set default button for cell %p", self);
  [self trySetAsDefaultButtonWithStrategy];
  
  NSDebugLog(@"NSButtonCell+Eau: enablePulsing completed successfully for button cell %p", self);
}

// Try multiple strategies to find the window and set default button
- (void) trySetAsDefaultButtonWithStrategy
{
  NSDebugLog(@"NSButtonCell+Eau: trySetAsDefaultButtonWithStrategy called for button cell %p", self);
  
  // Prevent multiple attempts for the same cell
  @synchronized(defaultButtonSetCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:(__bridge const void *)(self)];
    if ([defaultButtonSetCells containsObject:cellPtr]) {
      NSDebugLog(@"NSButtonCell+Eau: Button cell %p already processed, skipping", self);
      return;
    }
  }
  
  // Try immediate window access
  NSDebugLog(@"NSButtonCell+Eau: Trying direct window access for button cell %p", self);
  if ([self tryDirectWindowAccess]) {
    NSDebugLog(@"NSButtonCell+Eau: Direct window access succeeded for button cell %p", self);
    return;
  }
  
  // Search all windows for this button cell
  NSDebugLog(@"NSButtonCell+Eau: Trying to search all windows for button cell %p", self);
  if ([self trySearchAllWindows]) {
    NSDebugLog(@"NSButtonCell+Eau: Window search succeeded for button cell %p", self);
    return;
  }
  
  // Defensive: Check if this is a modal panel or modal window - if so, don't schedule delayed attempt
  // Modal windows are often short-lived and may be deallocated before timer fires
  NSView *controlView = nil;
  if ([self respondsToSelector:@selector(controlView)]) {
    controlView = [self controlView];
  }
  if (!controlView || ![controlView isKindOfClass:[NSView class]]) {
    NSDebugLog(@"NSButtonCell+Eau: Control view missing or invalid, skipping delayed attempt for cell %p", self);
    return;
  }

  NSWindow *window = nil;
  @try {
    window = [controlView window];
  } @catch (NSException *windowException) {
    NSDebugLog(@"NSButtonCell+Eau: Exception getting window for cell %p: %@", self, windowException);
    return;
  }

  if (!window || ![window isKindOfClass:[NSWindow class]]) {
    NSDebugLog(@"NSButtonCell+Eau: Window missing or invalid, skipping delayed attempt for cell %p", self);
    return;
  }

  // Skip delayed attempts for panels (short-lived)
  if ([window isKindOfClass:[NSPanel class]]) {
    NSDebugLog(@"NSButtonCell+Eau: Button is in a panel, skipping delayed attempt for cell %p", self);
    return;
  }

  // Skip delayed attempts for modal windows (short-lived, closed when modal session ends)
  if ([NSApp modalWindow] == window) {
    NSDebugLog(@"NSButtonCell+Eau: Button is in modal window, skipping delayed attempt for cell %p", self);
    return;
  }
  
  // Only schedule ONE delayed attempt to prevent loops
  NSDebugLog(@"NSButtonCell+Eau: Scheduling single delayed attempt for button cell %p", self);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self finalAttemptSetAsDefaultButton];
  });
}

// Final attempt to set as default button (only called once)
- (void) finalAttemptSetAsDefaultButton
{
  NSDebugLog(@"NSButtonCell+Eau: finalAttemptSetAsDefaultButton called for button cell %p", self);
  
  // Defensive: Verify self is still a valid object
  if (![self isKindOfClass:[NSButtonCell class]]) {
    NSDebugLog(@"NSButtonCell+Eau: Cell %p is no longer valid, aborting final attempt", self);
    return;
  }
  
  // Defensive: Check if the window still exists before proceeding
  NSView *controlView = nil;
  NSWindow *window = nil;
  
  if (![self respondsToSelector:@selector(controlView)]) {
    NSDebugLog(@"NSButtonCell+Eau: Cell does not respond to controlView, aborting");
    return;
  }
  
  controlView = [self controlView];
  if (!controlView) {
    NSDebugLog(@"NSButtonCell+Eau: Control view is nil in final attempt for cell %p", self);
    return;
  }
  
  // Validate controlView is actually a view before accessing it
  if (![controlView respondsToSelector:@selector(window)]) {
    NSDebugLog(@"NSButtonCell+Eau: Control view does not respond to window selector, aborting");
    return;
  }
  
  if (![controlView isKindOfClass:[NSView class]]) {
    NSDebugLog(@"NSButtonCell+Eau: Control view is not an NSView in final attempt for cell %p", self);
    return;
  }
  
  /* Getting the window can crash if view is deallocated - wrap in exception handler */
  @try {
    window = [controlView window];
  } @catch (NSException *windowException) {
    NSDebugLog(@"NSButtonCell+Eau: Exception getting window from control view for cell %p: %@", self, windowException);
    return;
  }
  
  if (!window) {
    NSDebugLog(@"NSButtonCell+Eau: Window is nil in final attempt for cell %p (window closed or view detached)", self);
    return;
  }
  
  if (![window isKindOfClass:[NSWindow class]]) {
    NSDebugLog(@"NSButtonCell+Eau: Window is not an NSWindow in final attempt for cell %p", self);
    return;
  }
  
  // Check if window is still visible - if not, it's being closed
  BOOL isVisible = NO;
  @try {
    isVisible = [window isVisible];
  } @catch (NSException *visException) {
    NSDebugLog(@"NSButtonCell+Eau: Exception checking window visibility for cell %p: %@", self, visException);
    return;
  }
  
  if (!isVisible) {
    NSDebugLog(@"NSButtonCell+Eau: Window is not visible in final attempt for cell %p, aborting", self);
    return;
  }
  
  // Check if already processed
  @synchronized(defaultButtonSetCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:(__bridge const void *)(self)];
    if ([defaultButtonSetCells containsObject:cellPtr]) {
      NSDebugLog(@"NSButtonCell+Eau: Button cell %p already processed in final attempt", self);
      return;
    }
  }
  
  // Try one more time with direct access
  if ([self tryDirectWindowAccess]) {
    NSDebugLog(@"NSButtonCell+Eau: Final direct window access succeeded for button cell %p", self);
    return;
  }
  
  // Try one more time with window search
  if ([self trySearchAllWindows]) {
    NSDebugLog(@"NSButtonCell+Eau: Final window search succeeded for button cell %p", self);
    return;
  }
  
  NSDebugLog(@"NSButtonCell+Eau: Final attempt failed for button cell %p - giving up", self);
}

// When highlighted, if this cell has a return icon image set internally, compute
// the title rect as if there was no image so the title doesn't shift while
// clicking. This mirrors NSCell's text layout and only applies for the highlighted
// state and when the stored images are the suppressed return images.
- (NSRect) titleRectForBounds:(NSRect)theRect
{
  BOOL hasReturnImage = NO;
  @synchronized(returnImageCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:(__bridge const void *)(self)];
    hasReturnImage = [returnImageCells containsObject:cellPtr];
  }

  if (hasReturnImage && [self isHighlighted]) {
    NSDebugLog(@"NSButtonCell+Eau: Suppressing layout image space for highlighted cell %p (return image), title rect adjusted", self);
    NSRect frame = [self drawingRectForBounds: theRect];
    if ([self isBordered] || [self isBezeled]) {
      frame.origin.x += 3;
      frame.size.width -= 6;
      frame.origin.y += 1;
      frame.size.height -= 2;
    }
    return frame;
  }

  return [super titleRectForBounds: theRect];
}

// Strategy 1: Try direct window access through controlView
- (BOOL) tryDirectWindowAccess
{
  NSDebugLog(@"NSButtonCell+Eau: tryDirectWindowAccess called for button cell %p", self);
  
  NSView *controlView = nil;
  if ([self respondsToSelector:@selector(controlView)]) {
    controlView = [self controlView];
    NSDebugLog(@"NSButtonCell+Eau: Found control view %p for button cell %p", controlView, self);
  }
  
  // Defensive: Check if controlView is still valid (not deallocated)
  if (!controlView || ![controlView isKindOfClass:[NSView class]]) {
    NSDebugLog(@"NSButtonCell+Eau: Control view is nil or invalid for button cell %p", self);
    return NO;
  }
  
  NSWindow *window = nil;
  
  if (controlView) {
    window = [controlView window];
    NSDebugLog(@"NSButtonCell+Eau: Found window %p for control view %p", window, controlView);
  
    
    if (!window) {
      // Try to find window by traversing the view hierarchy
      NSDebugLog(@"NSButtonCell+Eau: Traversing view hierarchy to find window for control view %p", controlView);
      NSView *currentView = controlView;
      while (currentView && !window) {
        @try {
          currentView = [currentView superview];
          // Defensive: Check if currentView is still valid before accessing
          if (currentView && [currentView isKindOfClass:[NSView class]]) {
            window = [currentView window];
            if (window) {
              NSDebugLog(@"NSButtonCell+Eau: Found window %p through view hierarchy traversal", window);
            }
          } else {
            // Invalid view in hierarchy, stop traversing
            break;
          }
        }
        @catch (NSException *hierarchyException) {
          NSDebugLog(@"NSButtonCell+Eau: ERROR traversing view hierarchy: %@", hierarchyException);
          break;
        }
      }
    }
    
    // Defensive: Check if window is still valid before using it
    if (window && [window isKindOfClass:[NSWindow class]]) {
      [self markAsDefaultButtonSet];
      NSDebugLog(@"NSButtonCell+Eau: Setting window %p default button cell to %p", window, self);
      [window setDefaultButtonCell:self];
      
      // Also make the button visually selected/highlighted
      [self safelyMakeButtonSelectedAndHighlighted];
      
      NSDebugLog(@"NSButtonCell+Eau: Successfully set default button cell for window %p", window);
      return YES;
    
    } else {
      NSDebugLog(@"NSButtonCell+Eau: No window found for control view %p", controlView);
    }
  } else {
    NSDebugLog(@"NSButtonCell+Eau: No control view found for button cell %p", self);
  }
  
  return NO;
}

// Replace layout-influencing image data while drawing so buttons don't shift as if the
// return icon were present. This temporarily clears private ivars that hold the images
// only if those images are the return images, then calls the original implementation.
- (void) EAU_drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView*)controlView
{
  BOOL shouldRemoveImagePosition = NO;
  NSCellImagePosition oldPos = [self imagePosition];

  @synchronized(returnImageCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:(__bridge const void *)(self)];
    if ([returnImageCells containsObject:cellPtr] && oldPos != NSNoImage) {
      shouldRemoveImagePosition = YES;
    }
  }

  if (shouldRemoveImagePosition) {
    @try {
      [self setImagePosition: NSNoImage];
    }
    @catch (NSException *e) {
      NSDebugLog(@"NSButtonCell+Eau: ERROR setting imagePosition to NSNoImage for cell %p: %@", self, e);
      shouldRemoveImagePosition = NO; // avoid restoring to wrong state
    }
  }

  // Call original implementation (swizzled). Keep this one guarded: it runs on
  // AppKit's display path, so an exception here must not escape into the draw
  // loop, and must not skip the imagePosition restore below (which would leave
  // the cell stuck at NSNoImage).
  @try {
    [self EAU_drawInteriorWithFrame:cellFrame inView:controlView];
  }
  @catch (NSException *e) {
    NSDebugLog(@"NSButtonCell+Eau: ERROR in EAU_drawInteriorWithFrame (original): %@", e);
  }
  if (shouldRemoveImagePosition) {
    [self setImagePosition: oldPos];

  }
}

// Ensure the cell is never narrower than its title text plus bezel padding,
// so translated strings (which can be much longer than the English source)
// always fit horizontally.  Also enforce at least METRICS_BUTTON_MIN_WIDTH
// for bezeled buttons so pill-shaped buttons have room around their text.
- (NSSize) EAU_cellSize
{
  NSSize size = [self EAU_cellSize]; // call original (swizzled)

  // Width needed for the title as actually rendered (using the cell's font)
  // plus horizontal bezel margins.  GNUstep's cellSize already adds border
  // + 6px, but recompute from the attributed title so the theme guarantees
  // translated text never clips regardless of the base implementation.
  if ([self respondsToSelector: @selector(attributedTitle)])
    {
      NSAttributedString *title = [self attributedTitle];
      if (title && [title length])
        {
          NSSize titleSize = [title size];
          GSThemeMargins m = [[GSTheme theme] buttonMarginsForCell: self
                                                             style: [self bezelStyle]
                                                             state: GSThemeNormalState];
          CGFloat minWidth = titleSize.width + m.left + m.right + 6 + 6;
          if (size.width < minWidth)
            size.width = minWidth;
        }
    }

  if (size.width < METRICS_BUTTON_MIN_WIDTH && [self isBezeled])
    {
      size.width = METRICS_BUTTON_MIN_WIDTH;
    }
  return size;
}

// Strategy 2: Search all windows for this button cell
- (BOOL) trySearchAllWindows
{
  NSDebugLog(@"NSButtonCell+Eau: trySearchAllWindows called for button cell %p", self);
  
  NSArray *windows = nil;
  if ([NSApp respondsToSelector:@selector(windows)]) {
    windows = [NSApp windows];
    NSDebugLog(@"NSButtonCell+Eau: Found %lu windows to search", (unsigned long)[windows count]);
  } else {
    NSDebugLog(@"NSButtonCell+Eau: NSApp does not respond to windows selector");
    return NO;
  }
  
  for (NSWindow *candidateWindow in windows) {
    @try {
      NSDebugLog(@"NSButtonCell+Eau: Searching window %p for button cell %p", candidateWindow, self);
      if ([self findButtonWithCellInWindow:candidateWindow]) {
        NSDebugLog(@"NSButtonCell+Eau: Found button cell %p in window %p", self, candidateWindow);
        [self markAsDefaultButtonSet];
        [candidateWindow setDefaultButtonCell:self];
        
        // Also make the button visually selected/highlighted
        [self safelyMakeButtonSelectedAndHighlighted];
        
        NSDebugLog(@"NSButtonCell+Eau: Successfully set default button cell for window %p", candidateWindow);
        return YES;
      }
    }
    @catch (NSException *windowSearchException) {
      NSDebugLog(@"NSButtonCell+Eau: ERROR searching window %p: %@", candidateWindow, windowSearchException);
      continue;
    }
  }
  
  NSDebugLog(@"NSButtonCell+Eau: Button cell %p not found in any of %lu windows", self, (unsigned long)[windows count]);
  
  return NO;
}

// Helper to mark this cell as having its default button set
- (void) markAsDefaultButtonSet
{
  @synchronized(defaultButtonSetCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:(__bridge const void *)(self)];
    [defaultButtonSetCells addObject:cellPtr];
    NSDebugLog(@"NSButtonCell+Eau: Marked button cell %p as default button set", self);
  }
}

// Recursively search for a button that has this cell
- (BOOL) findButtonWithCellInWindow:(NSWindow *)window
{
  NSView *contentView = [window contentView];
  if (contentView) {
    return [self findButtonWithCellInView:contentView];
  }
  return NO;
}

- (BOOL) findButtonWithCellInView:(NSView *)view
{
  if ([view isKindOfClass:[NSButton class]]) {
    NSButton *button = (NSButton*)view;
    if ([button cell] == self) {
      NSDebugLog(@"NSButtonCell+Eau: Found matching button %p for cell %p", button, self);
      return YES;
    }
  }
  
  // Recursively search subviews
  NSArray *subviews = [view subviews];
  if (subviews) {
    for (NSView *subview in subviews) {
      if ([self findButtonWithCellInView:subview]) {
        return YES;
      }
    }
  }
  
  return NO;
}

// Safely make the button selected and highlighted with extensive error handling
- (void) safelyMakeButtonSelectedAndHighlighted
{
  NSDebugLog(@"NSButtonCell+Eau: safelyMakeButtonSelectedAndHighlighted called for button cell %p", self);
  
  // DON'T set the cell as highlighted permanently - this interferes with pressed state detection
  // The default button appearance will come from the pulsing animation instead
  NSDebugLog(@"NSButtonCell+Eau: Skipping setHighlighted to allow proper pressed state detection");
  
  // DON'T set setShowsFirstResponder to avoid interfering with text field focus
    
  // Try to get the control view safely
  NSView *controlView = nil;
  if ([self respondsToSelector:@selector(controlView)]) {
    controlView = [self controlView];
    NSDebugLog(@"NSButtonCell+Eau: Found control view %p for button cell %p", controlView, self);
  } else {
    NSDebugLog(@"NSButtonCell+Eau: Button cell %p does not respond to controlView selector", self);
  }
  
  if (controlView && [controlView isKindOfClass:[NSButton class]]) {
    NSButton *button = (NSButton *)controlView;
    NSDebugLog(@"NSButtonCell+Eau: Control view is NSButton %p for cell %p", button, self);
    
    // Make the button highlighted with crash protection but without taking focus
    
    // Set as key equivalent for Enter/Return key handling but don't take focus
    NSDebugLog(@"NSButtonCell+Eau: Setting button %p properties for Return key handling", button);
    
    // Try to set as key equivalent if possible
    if ([button respondsToSelector:@selector(setKeyEquivalent:)]) {
      NSDebugLog(@"NSButtonCell+Eau: Setting button %p key equivalent to return", button);
      [button setKeyEquivalent:@"\r"];
    }
    
    // DON'T force the button cell to be highlighted - this interferes with pressed state detection
    // The default button appearance will come from the pulsing animation instead
    NSDebugLog(@"NSButtonCell+Eau: Skipping setHighlighted to preserve pressed state detection");
    
    // Force the button to redraw to show changes
    NSDebugLog(@"NSButtonCell+Eau: Marking button %p as needing display", button);
    [button setNeedsDisplay:YES];
    
    // Make this button the first responder ONLY if the current first responder is already a button
    NSWindow *window = [button window];
    if (window) {
      NSResponder *currentFirstResponder = [window firstResponder];
      NSDebugLog(@"NSButtonCell+Eau: Current first responder: %p (class: %@)", currentFirstResponder, [currentFirstResponder class]);
      
      if (currentFirstResponder && [currentFirstResponder isKindOfClass:[NSButton class]]) {
        NSDebugLog(@"NSButtonCell+Eau: Current first responder is a button, making default button %p first responder", button);
        [window makeFirstResponder:button];
      } else {
        NSDebugLog(@"NSButtonCell+Eau: Current first responder is not a button (%@), preserving focus", [currentFirstResponder class]);
      }
    } else {
      NSDebugLog(@"NSButtonCell+Eau: No window found for button %p", button);
    }
    
    NSDebugLog(@"NSButtonCell+Eau: Successfully configured button %p with conditional focus", button);
  
  } else {
    NSDebugLog(@"NSButtonCell+Eau: Control view %p is not an NSButton or is nil for cell %p", controlView, self);
  }
}

// Clean up when the cell is deallocated
- (void) dealloc
{
  NSDebugLog(@"NSButtonCell+Eau: dealloc called for button cell %p", self);
  
  // Cancel any pending operations
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  
  // Remove from tracking sets
  @synchronized(processingCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:(__bridge const void *)(self)];
    [processingCells removeObject:cellPtr];
  }
  
  @synchronized(defaultButtonSetCells) {
    NSValue *cellPtr = [NSValue valueWithPointer:(__bridge const void *)(self)];
    [defaultButtonSetCells removeObject:cellPtr];
  }
  
  NSDebugLog(@"NSButtonCell+Eau: Cleanup completed for button cell %p", self);
}

// Timer callback for default button pulse — called from NSButton+Eau.m swizzle
- (void) EauPulseTick: (NSTimer *)timer
{
  [[self controlView] setNeedsDisplay: YES];
  [[[self controlView] window] display];
  [[[self controlView] window] flushWindow];
}
@end