// The purpose of this code is to draw command key equivalents in the menu using the Command key symbol

#import "Eau.h"
#import "NSMenuItemCell+Eau.h"
#import <objc/runtime.h>

// Category on NSMenuItemCell used for method swizzling
@interface NSMenuItemCell (EauSwizzling)
- (CGFloat)eau_titleWidth;
- (NSRect)eau_titleRectForBounds:(NSRect)cellFrame;
- (NSColor *)eau_textColor;
- (void)eau_drawImageWithFrame:(NSRect)cellFrame inView:(NSView*)controlView;
- (CGFloat)eau_imageWidth;
- (NSRect)eau_imageRectForBounds:(NSRect)cellFrame;
@end

@implementation NSMenuItemCell (EauSwizzling)

// Swizzled implementation for titleWidth - adds padding
- (CGFloat)eau_titleWidth {
  NSDebugLog(@"NSMenuItemCell+Eau: eau_titleWidth called");

  // After swizzling, this message sends the original titleWidth implementation
  CGFloat originalWidth = [self eau_titleWidth];
  CGFloat paddedWidth = originalWidth + EAU_MENU_ITEM_PADDING;

  NSDebugLog(@"NSMenuItemCell+Eau: eau_titleWidth originalWidth=%f paddedWidth=%f", originalWidth, paddedWidth);

  return paddedWidth;
}

// Swizzled implementation for titleRectForBounds: - shifts title to center in
// padded space and corrects the title offset for a capped icon width.
- (NSRect)eau_titleRectForBounds:(NSRect)cellFrame {
  NSDebugLog(@"NSMenuItemCell+Eau: eau_titleRectForBounds: called with cellFrame=(%f, %f, %f, %f)",
        cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);

  // After swizzling, this message sends the original titleRectForBounds: implementation
  NSRect originalRect = [self eau_titleRectForBounds:cellFrame];

  // GNUstep's original offsets the title by the RAW image width (_imageWidth),
  // which is the full icon size (e.g. 128px).  The image column is capped to
  // the theme's icon size, so pull the title back left by the difference,
  // otherwise text lands far to the right of a small icon.
  NSMenuItem *item = [self menuItem];
  NSImage *image = [item image];
  NSString *title = [item title];
  if (image && title && [title length] > 0)
    {
      NSSize imgSize = [image size];
      CGFloat rawWidth = imgSize.width;
      CGFloat iconSize = [(Eau *)[GSTheme theme] menuItemIconSize];
      CGFloat cappedWidth = MIN(rawWidth, iconSize);
      if (rawWidth > cappedWidth)
        {
          CGFloat delta = rawWidth - cappedWidth;
          originalRect.origin.x -= delta;
          originalRect.size.width += delta;
        }
    }

  // Shift by half padding to horizontally center in padded space
  originalRect.origin.x += (EAU_MENU_ITEM_PADDING / 2.0);

  NSDebugLog(@"NSMenuItemCell+Eau: eau_titleRectForBounds: returning rect=(%f, %f, %f, %f)",
        originalRect.origin.x, originalRect.origin.y, originalRect.size.width, originalRect.size.height);

  return originalRect;
}

// Swizzled implementation for textColor - returns lighter grey for disabled menu items
- (NSColor *)eau_textColor {
  if (![self isEnabled]) {
    return [NSColor colorWithCalibratedWhite: 0.65 alpha: 1.0];
  }
  return [self eau_textColor];
}

// Swizzled implementation for drawImageWithFrame:inView: —
// when image IS the title (image + empty title), draw centered in full cell;
// when the item has both an icon and a title, scale the icon down to the
// theme's menuItemIconSize so a large app/prefPane icon renders small.
- (void)eau_drawImageWithFrame:(NSRect)cellFrame inView:(NSView*)controlView
{
  NSMenuItem *item = [self menuItem];
  NSImage *image = [item image];
  NSString *title = [item title];
  if (image)
    {
      NSSize imgSize = [image size];
      if (!title || [title length] == 0)
        {
          /* Image is the whole item - draw centered in the full cell. */
          CGFloat scale = MIN(cellFrame.size.width / imgSize.width,
                              cellFrame.size.height / imgSize.height);
          if (scale > 1.0) scale = 1.0;
          NSSize drawSize = NSMakeSize(imgSize.width * scale,
                                       imgSize.height * scale);
          NSPoint drawPoint = NSMakePoint(NSMidX(cellFrame) - drawSize.width / 2,
                                          NSMidY(cellFrame) - drawSize.height / 2);
          [image drawInRect: NSMakeRect(drawPoint.x, drawPoint.y,
                                        drawSize.width, drawSize.height)
                   fromRect: NSZeroRect
                  operation: NSCompositeSourceOver
                   fraction: 1.0];
          return;
        }
      else
        {
          /* Icon next to a title: draw in the (capped) image column rect,
             scaled down (never up) to fit the theme's icon size. */
          NSRect imageRect = [self imageRectForBounds: cellFrame];
          CGFloat iconSize = [(Eau *)[GSTheme theme] menuItemIconSize];
          if (imageRect.size.width > iconSize)
            imageRect.size.width = iconSize;
          CGFloat scale = MIN(imageRect.size.width / imgSize.width,
                              imageRect.size.height / imgSize.height);
          if (scale > 1.0) scale = 1.0;
          NSSize drawSize = NSMakeSize(imgSize.width * scale,
                                       imgSize.height * scale);
          NSPoint drawPoint = NSMakePoint(NSMidX(imageRect) - drawSize.width / 2,
                                          NSMidY(imageRect) - drawSize.height / 2);
          [image drawInRect: NSMakeRect(drawPoint.x, drawPoint.y,
                                        drawSize.width, drawSize.height)
                   fromRect: NSZeroRect
                  operation: NSCompositeSourceOver
                   fraction: 1.0];
          return;
        }
    }
  [self eau_drawImageWithFrame: cellFrame inView: controlView];
}

/* Cap the image column width so a large app/prefPane icon does not widen the
   whole menu.  NSMenuView lays out the menu using imageWidth, so it must be
   capped too - not just the drawn image. */
- (CGFloat)eau_imageWidth
{
  CGFloat width = [self eau_imageWidth];
  CGFloat iconSize = [(Eau *)[GSTheme theme] menuItemIconSize];
  if (width > iconSize)
    return iconSize;
  return width;
}

/* Cap the image rect width to the same icon size.  The default rect is as
   wide as the image itself; drawing into a capped rect keeps the icon small
   and aligned in the image column. */
- (NSRect)eau_imageRectForBounds:(NSRect)cellFrame
{
  NSRect rect = [self eau_imageRectForBounds: cellFrame];
  CGFloat iconSize = [(Eau *)[GSTheme theme] menuItemIconSize];
  if (rect.size.width > iconSize)
    rect.size.width = iconSize;
  return rect;
}

@end

// This function runs when the bundle is loaded
__attribute__((constructor))
static void initMenuItemCellSwizzling(void) {
  // NSLog(@"NSMenuItemCell+Eau: Constructor called - setting up swizzling");

  Class menuItemCellClass = objc_getClass("NSMenuItemCell");
  if (!menuItemCellClass) {
    NSLog(@"NSMenuItemCell+Eau: ERROR - NSMenuItemCell class not found");
    return;
  }

  // Swizzle titleWidth - this is what NSMenuView uses to calculate item widths
  SEL titleWidthSelector = sel_registerName("titleWidth");
  Method originalTitleWidthMethod = class_getInstanceMethod(menuItemCellClass, titleWidthSelector);
  Method swizzledTitleWidthMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_titleWidth));
  if (originalTitleWidthMethod && swizzledTitleWidthMethod) {
    // Avoid double-swizzling
    IMP originalIMP = method_getImplementation(originalTitleWidthMethod);
    IMP swizzledIMP = method_getImplementation(swizzledTitleWidthMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalTitleWidthMethod, swizzledTitleWidthMethod);
      // NSLog(@"NSMenuItemCell+Eau: Successfully swizzled titleWidth method");
    } else {
      // NSLog(@"NSMenuItemCell+Eau: titleWidth already swizzled, skipping");
    }
  } else {
    if (!originalTitleWidthMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find original titleWidth method");
    }
    if (!swizzledTitleWidthMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find eau_titleWidth method on NSMenuItemCell");
    }
  }

  // Swizzle titleRectForBounds: - this positions the title text
  SEL titleRectSelector = sel_registerName("titleRectForBounds:");
  Method originalTitleRectMethod = class_getInstanceMethod(menuItemCellClass, titleRectSelector);
  Method swizzledTitleRectMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_titleRectForBounds:));
  if (originalTitleRectMethod && swizzledTitleRectMethod) {
    // Avoid double-swizzling
    IMP originalIMP = method_getImplementation(originalTitleRectMethod);
    IMP swizzledIMP = method_getImplementation(swizzledTitleRectMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalTitleRectMethod, swizzledTitleRectMethod);
      // NSLog(@"NSMenuItemCell+Eau: Successfully swizzled titleRectForBounds: method");
    } else {
      // NSLog(@"NSMenuItemCell+Eau: titleRectForBounds: already swizzled, skipping");
    }
  } else {
    if (!originalTitleRectMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find original titleRectForBounds: method");
    }
    if (!swizzledTitleRectMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find eau_titleRectForBounds: method on NSMenuItemCell");
    }
  }

  // Swizzle textColor - returns lighter grey for disabled items
  SEL textColorSelector = sel_registerName("textColor");
  Method originalTextColorMethod = class_getInstanceMethod(menuItemCellClass, textColorSelector);
  Method swizzledTextColorMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_textColor));
  if (originalTextColorMethod && swizzledTextColorMethod) {
    IMP originalIMP = method_getImplementation(originalTextColorMethod);
    IMP swizzledIMP = method_getImplementation(swizzledTextColorMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalTextColorMethod, swizzledTextColorMethod);
    }
  } else {
    if (!originalTextColorMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find original textColor method");
    }
    if (!swizzledTextColorMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find eau_textColor method on NSMenuItemCell");
    }
  }

  // Swizzle drawImageWithFrame:inView: — draws image centered in full cell
  // when the image IS the menu title (image + empty title)
  SEL drawImageSelector = sel_registerName("drawImageWithFrame:inView:");
  Method originalDrawImageMethod = class_getInstanceMethod(menuItemCellClass, drawImageSelector);
  Method swizzledDrawImageMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_drawImageWithFrame:inView:));
  if (originalDrawImageMethod && swizzledDrawImageMethod) {
    IMP originalIMP = method_getImplementation(originalDrawImageMethod);
    IMP swizzledIMP = method_getImplementation(swizzledDrawImageMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalDrawImageMethod, swizzledDrawImageMethod);
    }
  } else {
    if (!originalDrawImageMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find original drawImageWithFrame:inView: method");
    }
    if (!swizzledDrawImageMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find eau_drawImageWithFrame:inView: method on NSMenuItemCell");
    }
  }

  // Swizzle imageWidth - caps the image column so large icons stay small
  SEL imageWidthSelector = sel_registerName("imageWidth");
  Method originalImageWidthMethod = class_getInstanceMethod(menuItemCellClass, imageWidthSelector);
  Method swizzledImageWidthMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_imageWidth));
  if (originalImageWidthMethod && swizzledImageWidthMethod) {
    IMP originalIMP = method_getImplementation(originalImageWidthMethod);
    IMP swizzledIMP = method_getImplementation(swizzledImageWidthMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalImageWidthMethod, swizzledImageWidthMethod);
    }
  } else {
    NSLog(@"NSMenuItemCell+Eau: WARNING - Could not swizzle imageWidth (orig=%p swiz=%p)",
      originalImageWidthMethod, swizzledImageWidthMethod);
  }

  // Swizzle imageRectForBounds: - caps the image draw rect to icon size
  SEL imageRectSelector = sel_registerName("imageRectForBounds:");
  Method originalImageRectMethod = class_getInstanceMethod(menuItemCellClass, imageRectSelector);
  Method swizzledImageRectMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_imageRectForBounds:));
  if (originalImageRectMethod && swizzledImageRectMethod) {
    IMP originalIMP = method_getImplementation(originalImageRectMethod);
    IMP swizzledIMP = method_getImplementation(swizzledImageRectMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalImageRectMethod, swizzledImageRectMethod);
    }
  } else {
    NSLog(@"NSMenuItemCell+Eau: WARNING - Could not swizzle imageRectForBounds: (orig=%p swiz=%p)",
      originalImageRectMethod, swizzledImageRectMethod);
  }
}

@implementation Eau(NSMenuItemCell)

// Override drawKeyEquivalentWithFrame to intercept just the key equivalent drawing
- (void) _overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  NSDebugLog(@"_overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame:inView:");
  NSMenuItemCell *xself = (NSMenuItemCell*)self;
  [xself EAUdrawKeyEquivalentWithFrame:cellFrame inView:controlView];
}

@end

@implementation NSMenuItemCell (EauTheme)

- (void) EAUdrawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
  NSMenuItem *menuItem = [self menuItem];
  NSRect keyEquivRect = [self keyEquivalentRectForBounds: cellFrame];
  
  // First, draw the submenu arrow if this item has a submenu
  if ([menuItem hasSubmenu]) {
    NSImage *arrow = nil;
    
    if ([self isHighlighted]) {
      arrow = [NSImage imageNamed: @"NSHighlightedMenuArrow"];
    }
    if (arrow == nil) {
      arrow = [NSImage imageNamed: @"NSMenuArrow"];
    }
    // Fall back to common arrow images if NSMenuArrow is not found
    if (arrow == nil) {
      if ([self isHighlighted]) {
        arrow = [NSImage imageNamed: @"common_3DArrowRightH"];
      } else {
        arrow = [NSImage imageNamed: @"common_3DArrowRight"];
      }
    }
    
    if (arrow != nil) {
      NSSize size = [arrow size];
      NSPoint position;
      
      position.x = keyEquivRect.origin.x + keyEquivRect.size.width - size.width;
      position.y = MAX(NSMidY(keyEquivRect) - (size.height / 2.0), 0.0);
      
      // Adjust for flipped view
      if ([controlView isFlipped]) {
        position.y += size.height;
      }
      
      [arrow compositeToPoint: position operation: NSCompositeSourceOver];
      
      NSDebugLog(@"NSMenuItemCell+Eau: Drew submenu arrow at position: {%.1f, %.1f} size: {%.1f, %.1f}",
             position.x, position.y, size.width, size.height);
    } else {
      NSDebugLog(@"NSMenuItemCell+Eau: WARNING - No arrow image found for submenu item '%@'", [menuItem title]);
    }
    return; // Submenu items don't have key equivalents, so we're done
  }
  
  // For non-submenu items, handle key equivalents
  if (menuItem != nil) {
    NSString *originalKeyEquivalent = [menuItem keyEquivalent];
    NSUInteger modifierMask = [menuItem keyEquivalentModifierMask];
    
    NSDebugLog(@"NSMenuItemCell+Eau: Drawing key equivalent for '%@': '%@', modifiers: %lu", 
           [menuItem title], originalKeyEquivalent, (unsigned long)modifierMask);
    
    // Convert the key equivalent to Mac style if needed
    if (originalKeyEquivalent && [originalKeyEquivalent length] > 0) {
      NSString *macStyleKeyEquivalent = [self EAUconvertKeyEquivalentToMacStyle:originalKeyEquivalent withModifiers:modifierMask];
      
      if (![macStyleKeyEquivalent isEqualToString:originalKeyEquivalent]) {
        NSDebugLog(@"NSMenuItemCell+Eau: Drawing Mac style key equivalent '%@' instead of '%@'", macStyleKeyEquivalent, originalKeyEquivalent);
        
        // Draw the Mac-style key equivalent manually
        NSFont *font = [NSFont menuFontOfSize:0];
        NSColor *textColor = [self textColor];
        
        NSDictionary *attributes = @{
          NSFontAttributeName: font,
          NSForegroundColorAttributeName: textColor
        };
        
        // Calculate the size and position for right-aligned text
        NSSize textSize = [macStyleKeyEquivalent sizeWithAttributes:attributes];
        NSRect textRect = keyEquivRect;
        textRect.origin.x = NSMaxX(keyEquivRect) - textSize.width - 4; // 4 pixel margin from right
        textRect.origin.y = keyEquivRect.origin.y + (keyEquivRect.size.height - textSize.height) / 2;
        textRect.size = textSize;
        
        [macStyleKeyEquivalent drawInRect:textRect withAttributes:attributes];
        
        NSDebugLog(@"NSMenuItemCell+Eau: Drew Mac style key equivalent at rect: {{%.1f, %.1f}, {%.1f, %.1f}}", 
               textRect.origin.x, textRect.origin.y, textRect.size.width, textRect.size.height);
        return;
      }
    }
  }
  
  // If no conversion needed, do nothing - let the normal drawing process handle it
  NSDebugLog(@"NSMenuItemCell+Eau: No conversion needed, skipping custom drawing");
}

- (NSString*) EAUconvertKeyEquivalentToMacStyle: (NSString*)keyEquivalent withModifiers: (NSUInteger)modifierMask
{
  NSDebugLog(@"NSMenuItemCell+Eau: Converting key equivalent '%@' with modifiers %lu", keyEquivalent, (unsigned long)modifierMask);
  
  if (!keyEquivalent || [keyEquivalent length] == 0) {
    return keyEquivalent;
  }
  
  // Handle the old "#key" format first (this is what you're seeing)
  if ([keyEquivalent hasPrefix:@"#"] && [keyEquivalent length] > 1) {
    NSString *key = [keyEquivalent substringFromIndex:1];
    NSString *result = [NSString stringWithFormat:@"⌘%@", [key uppercaseString]];
    
    NSDebugLog(@"NSMenuItemCell+Eau: Converted old format '%@' to Mac style: '%@'", keyEquivalent, result);
    return result;
  }
  
  // Check if command modifier is present
  if (modifierMask & NSCommandKeyMask) {
    NSMutableString *result = [NSMutableString string];
    
    // Add modifier symbols in the correct order (following Mac conventions)
    if (modifierMask & NSControlKeyMask) {
      [result appendString:@"⌃"]; // Control symbol
    }
    if (modifierMask & NSAlternateKeyMask) {
      [result appendString:@"⌥"]; // Option/Alt symbol  
    }
    if (modifierMask & NSCommandKeyMask) {
      [result appendString:@"⌘"]; // Command symbol
    }
    if (modifierMask & NSShiftKeyMask) {
      [result appendString:@"⇧"]; // Shift symbol (after Command)
    }
    
    // Convert key equivalent to uppercase if it's a letter, or to symbol for special keys
    NSString *keyToAdd = keyEquivalent;
    if ([keyEquivalent length] == 1) {
      unichar ch = [keyEquivalent characterAtIndex:0];
      if (ch >= 'a' && ch <= 'z') {
        keyToAdd = [keyEquivalent uppercaseString];
      } else if (ch == 8 || ch == 127) { // Backspace or Delete
        keyToAdd = @"⌫";
      } else if (ch == 27) { // Escape
        keyToAdd = @"⎋";
      } else if (ch == 9) { // Tab
        keyToAdd = @"⇥";
      } else if (ch == 13) { // Return/Enter
        keyToAdd = @"↵";
      } else if (ch == 32) { // Space
        keyToAdd = @"␣";
      }
    } else if ([keyEquivalent length] > 1) {
      // Handle arrow keys and other multi-character key names
      NSString *lower = [keyEquivalent lowercaseString];
      if ([lower isEqualToString:@"left"]) {
        keyToAdd = @"←";
      } else if ([lower isEqualToString:@"right"]) {
        keyToAdd = @"→";
      } else if ([lower isEqualToString:@"up"]) {
        keyToAdd = @"↑";
      } else if ([lower isEqualToString:@"down"]) {
        keyToAdd = @"↓";
      }
    }
    
    [result appendString:keyToAdd];
    
    NSDebugLog(@"NSMenuItemCell+Eau: Converted to Mac style: '%@'", result);
    return result;
  }
  
  NSDebugLog(@"NSMenuItemCell+Eau: No conversion needed for '%@'", keyEquivalent);
  return keyEquivalent;
}

@end
