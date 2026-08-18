#import "GSInfoPanel+Eau.h"
#import "Eau.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSTask.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <GNUstepGUI/GSTheme.h>

#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// URL button — shows pointing-hand cursor on hover, no highlight
// ---------------------------------------------------------------------------
@interface _EauURLButton : NSButton
@end

@implementation _EauURLButton
- (void)resetCursorRects
{
  [super resetCursorRects];
  [self addCursorRect: [self bounds]
               cursor: [NSCursor pointingHandCursor]];
}
@end

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

@implementation GSInfoPanel (Eau)

+ (void)load
{
  static BOOL swizzled = NO;
  if (!swizzled)
    {
      swizzled = YES;

      Class class = [self class];

      {
        SEL originalSelector = @selector(initWithDictionary:);
        SEL swizzledSelector = @selector(eau_initWithDictionary:);

        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

        BOOL didAddMethod = class_addMethod(class,
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));

        if (didAddMethod)
          {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
          }
        else
          {
            method_exchangeImplementations(originalMethod, swizzledMethod);
          }
      }

      {
        SEL originalSelector = @selector(setTitle:);
        SEL swizzledSelector = @selector(eau_setTitle:);

        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

        BOOL didAddMethod = class_addMethod(class,
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));

        if (didAddMethod)
          {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
          }
        else
          {
            method_exchangeImplementations(originalMethod, swizzledMethod);
          }
      }
    }
  }

static char kEauAppNameKey;

- (id)eau_initWithDictionary:(NSDictionary *)dictionary
     __attribute__((objc_method_family(init)))
{
  // ---- 1. Let the original build the full panel (side-by-side layout) ----
  if (dictionary == nil)
    dictionary = [NSDictionary dictionary];
  id result = [self eau_initWithDictionary:dictionary];
  if (!result) return nil;

  // ---- 2. Collect references to every view the original created ----
  NSView *cv = [result contentView];
  NSArray *subs = [[cv subviews] copy];

  NSButton *iconButton = nil;
  NSTextField *nameLabel = nil;
  NSTextField *descriptionLabel = nil;
  NSTextField *versionLabel = nil;
  NSTextField *authorTitleLabel = nil;
  NSView      *authorsList = nil;
  NSTextField *urlLabel = nil;
  NSTextField *copyrightLabel = nil;
  NSTextField *copyrightDescriptionLabel = nil;
  NSButton    *themeLabel = nil;

  for (NSView *v in subs)
    {
      // Background image — skip
      if ([v isKindOfClass: [NSImageView class]]) continue;

      // NSButtons: icon has an image, theme label targets GSTheme
      if ([v isKindOfClass: [NSButton class]])
        {
          NSButton *b = (NSButton *)v;
          if ([b image])
            {
              iconButton = b;
              // If no app-specific icon was found, skip the generic GNUstep
              // logo and use the theme's default application icon instead.
              if ([[[b image] name] isEqualToString: @"NSApplicationIcon"])
                [b setImage: [NSApp applicationIconImage]];
              // Prevent focus ring / highlight on the icon
              [b setFocusRingType: NSFocusRingTypeNone];
              [b setRefusesFirstResponder: YES];
            }
          else
            {
              themeLabel = b;
              // Prevent focus ring / highlight on the theme label
              [b setFocusRingType: NSFocusRingTypeNone];
              [b setRefusesFirstResponder: YES];
            }
          continue;
        }

      // NSTextFields
      if ([v isKindOfClass: [NSTextField class]])
        {
          NSTextField *tf = (NSTextField *)v;
          NSString *val = [tf stringValue];
          CGFloat fs = [[tf font] pointSize];

          if (fs >= 30)
            {
              // Name label — make smaller and centered
              nameLabel = tf;
              [tf setFont: [NSFont boldSystemFontOfSize: 20]];
              [tf setAlignment: NSCenterTextAlignment];
              [tf sizeToFit];
            }
          else if (fs >= 13 && !descriptionLabel && ![val hasPrefix: @"Release:"]
                   && ![val hasPrefix: @"Author"] && ![val hasPrefix: @"Copyright"])
            {
              descriptionLabel = tf;
              [tf setAlignment: NSCenterTextAlignment];
            }
          else if ([val hasPrefix: @"Release:"])
            {
              versionLabel = tf;
              [tf setAlignment: NSCenterTextAlignment];
              // Dedup: if version is "Release: X (X)", strip to "Release: X"
              NSRange pr = [val rangeOfString: @" ("];
              if (pr.location != NSNotFound)
                {
                  NSString *before = [val substringToIndex: pr.location];
                  NSString *after  = [val substringFromIndex: pr.location + 2];
                  if ([after hasSuffix: @")"])
                    {
                      NSString *inner = [after substringToIndex: [after length] - 1];
                      NSString *vPart = [before substringFromIndex:
                        [_(@"Release: ") length]];
                      if ([vPart isEqualToString: inner])
                        {
                          [tf setStringValue: before];
                          [tf sizeToFit];
                        }
                    }
                }
            }
          else if ([val hasPrefix: @"Author:"] || [val hasPrefix: @"Authors:"])
            {
              authorTitleLabel = tf;
            }
          else if ([val hasSuffix: @".org"] || [val hasSuffix: @".com"]
                   || [val hasPrefix: @"http"] || [val hasPrefix: @"See "])
            {
              urlLabel = tf;
              [tf setAlignment: NSCenterTextAlignment];
            }
          else if ([val hasPrefix: @"Copyright"] && !copyrightLabel)
            {
              copyrightLabel = tf;
              [tf setAlignment: NSCenterTextAlignment];
            }
          else
            {
              copyrightDescriptionLabel = tf;
              [tf setAlignment: NSCenterTextAlignment];
            }
          continue;
        }

      // _GSLabelListView for authors
      {
        NSString *cn = NSStringFromClass([v class]);
        if ([cn isEqualToString: @"_GSLabelListView"])
          authorsList = v;
      }
    }

  // ---- 3. Create combined author field ("Authors:" + names, one field) ----
  NSTextField *authorField = nil;
  if (authorsList)
    {
      // Grab the prefix from the title label ("Author: " or "Authors: ")
      NSString *prefix = [authorTitleLabel stringValue];
      if ([prefix length] > 0)
        {
          // Extract individual author names from the list view
          NSMutableArray *names = [NSMutableArray array];
          for (NSView *sub in [authorsList subviews])
            {
              if ([sub isKindOfClass: [NSTextField class]])
                [names addObject: [(NSTextField *)sub stringValue]];
            }
          // _GSLabelListView stores subviews bottom-to-top, so reverse
          // to match the original plist order.
          for (NSUInteger i = 0; i < [names count] / 2; i++)
            [names exchangeObjectAtIndex: i
                      withObjectAtIndex: [names count] - 1 - i];

          // Build combined text
          NSMutableString *txt = [NSMutableString string];
          if ([names count] == 1)
            {
              // Single author: "Author: Name" on one line
              [txt appendString: prefix];
              [txt appendString: [names objectAtIndex: 0]];
            }
          else if ([names count] > 1)
            {
              // Multiple authors: "Authors:" first line, each name below
              [txt appendString: prefix];
              for (NSString *n in names)
                [txt appendFormat: @"\n%@", n];
            }

          if ([txt length] > 0)
            {
              authorField = AUTORELEASE([NSTextField new]);
              [authorField setStringValue: txt];
              [authorField setDrawsBackground: NO];
              [authorField setEditable: NO];
              [authorField setSelectable: NO];
              [authorField setBezeled: NO];
              [authorField setBordered: NO];
              [authorField setAlignment: NSCenterTextAlignment];
              [authorField setFont: [NSFont systemFontOfSize: 12]];
              [[authorField cell] setWraps: YES];
              [[authorField cell] setScrollable: NO];
              [authorField sizeToFit];
              // Cap width so multi-line text wraps within the window
              if (NSWidth([authorField frame]) > 288.0)
                {
                  NSRect af0 = [authorField frame];
                  af0.size.width = 288.0;
                  [authorField setFrame: af0];
                  [authorField sizeToFit];
                }
            }
        }
    }

  // ---- 4. Create URL button (clickable link) ----
  NSButton *urlButton = nil;
  if (urlLabel)
    {
      urlButton = AUTORELEASE([_EauURLButton new]);
      [urlButton setTitle: _(@"Website")];
      [urlButton setBordered: NO];
      [urlButton setFocusRingType: NSFocusRingTypeNone];
      [urlButton setRefusesFirstResponder: YES];
      [urlButton setAlignment: NSCenterTextAlignment];
      [urlButton setFont: [NSFont systemFontOfSize: 12]];
      [urlButton setTarget: self];
      [urlButton setAction: @selector(_eau_openURL:)];
      [urlButton sizeToFit];
      objc_setAssociatedObject(urlButton, &kEauAppNameKey,
                               [urlLabel stringValue],
                               OBJC_ASSOCIATION_COPY);
    }

  // ---- 5. Remove everything and rebuild centered ----
  for (NSView *v in subs) [v removeFromSuperview];

  // Measure each element
  CGFloat iconSize = NSHeight([iconButton frame]);
  CGFloat nameH = NSHeight([nameLabel frame]);
  CGFloat descH = descriptionLabel ? NSHeight([descriptionLabel frame]) : 0;
  CGFloat verH = NSHeight([versionLabel frame]);
  CGFloat authH = authorField ? NSHeight([authorField frame]) : 0;
  CGFloat urlH = urlButton ? NSHeight([urlButton frame]) : 0;
  CGFloat crH = NSHeight([copyrightLabel frame]);
  CGFloat crDescH = copyrightDescriptionLabel ? NSHeight([copyrightDescriptionLabel frame]) : 0;
  CGFloat themeH = NSHeight([themeLabel frame]);

  // Find the widest element
  __block CGFloat maxW = 288.0; // 360 - 36*2 margin
  void (^widen)(NSView *) = ^(NSView *v) {
    if (!v) return;
    CGFloat w = NSWidth([v frame]);
    if (w > maxW) maxW = w;
  };
  widen(nameLabel);
  widen(descriptionLabel);
  widen(versionLabel);
  if (authorField) {
    CGFloat w = NSWidth([authorField frame]);
    if (w > maxW) maxW = w;
  }
  if (urlButton) { CGFloat w = NSWidth([urlButton frame]); if (w > maxW) maxW = w; }
  widen(copyrightLabel);
  widen(copyrightDescriptionLabel);
  widen(themeLabel);

  // Reflow any text fields that exceed the content width
  {
    CGFloat cw = maxW; // content width is already capped at 288
    void (^reflow)(NSTextField *) = ^(NSTextField *tf) {
      if (!tf || NSWidth([tf frame]) <= cw) return;
      NSRect f = [tf frame];
      f.size.width = cw;
      [tf setFrame: f];
      [[tf cell] setWraps: YES];
      [[tf cell] setScrollable: NO];
      [tf sizeToFit];
    };
    reflow(descriptionLabel);
    reflow(versionLabel);
    reflow(copyrightLabel);
    reflow(copyrightDescriptionLabel);
    // Re-measure heights after reflow
    descH = descriptionLabel ? NSHeight([descriptionLabel frame]) : 0;
    verH = NSHeight([versionLabel frame]);
    crH = NSHeight([copyrightLabel frame]);
    crDescH = copyrightDescriptionLabel ? NSHeight([copyrightDescriptionLabel frame]) : 0;
  }

  // Calculate window size for centered vertical layout
  CGFloat margin = 36.0;
  CGFloat gap = 6.0;

  CGFloat totalW = 360.0;
  CGFloat totalH = margin
                 + iconSize
                 + gap + nameH
                 + (descH > 0 ? gap + descH : 0)
                 + gap + verH
                 + (authH > 0 ? gap + authH : 0)
                 + (urlH > 0 ? gap + urlH : 0)
                 + gap + crH
                 + (crDescH > 0 ? gap + crDescH : 0)
                 + gap + themeH
                 + margin;

  // Resize the window
  NSRect wf = [result frame];
  [result setFrame: NSMakeRect(wf.origin.x, wf.origin.y, totalW, totalH)
           display: NO];

  // ---- 4. Layout views centered vertically ----
  CGFloat cx = totalW / 2.0;
  CGFloat y = totalH - margin;

  // Icon
  {
    NSRect f = [iconButton frame];
    f.size.width = iconSize;  f.size.height = iconSize;
    y -= NSHeight(f);
    f.origin.x = cx - NSWidth(f) / 2.0;
    f.origin.y = y;
    [iconButton setFrame: f];
    [cv addSubview: iconButton];
  }

  y -= gap;

  // Name
  {
    NSRect f = [nameLabel frame];
    y -= NSHeight(f);
    f.origin.x = cx - NSWidth(f) / 2.0;
    f.origin.y = y;
    [nameLabel setFrame: f];
    [cv addSubview: nameLabel];
  }

  // Description
  if (descriptionLabel)
    {
      y -= gap;
      NSRect f = [descriptionLabel frame];
      y -= NSHeight(f);
      f.origin.x = cx - NSWidth(f) / 2.0;
      f.origin.y = y;
      [descriptionLabel setFrame: f];
      [cv addSubview: descriptionLabel];
    }

  y -= gap;

  // Version
  {
    NSRect f = [versionLabel frame];
    y -= NSHeight(f);
    f.origin.x = cx - NSWidth(f) / 2.0;
    f.origin.y = y;
    [versionLabel setFrame: f];
    [cv addSubview: versionLabel];
  }

  y -= gap;

  // Authors (combined "Authors:" + names, centered)
  if (authorField)
    {
      y -= gap;
      NSRect f = [authorField frame];
      y -= NSHeight(f);
      f.origin.x = cx - NSWidth(f) / 2.0;
      f.origin.y = y;
      [authorField setFrame: f];
      [cv addSubview: authorField];
    }

  // URL (clickable link)
  if (urlButton)
    {
      y -= gap;
      NSRect f = [urlButton frame];
      y -= NSHeight(f);
      f.origin.x = cx - NSWidth(f) / 2.0;
      f.origin.y = y;
      [urlButton setFrame: f];
      [cv addSubview: urlButton];
    }

  y -= gap;

  // Copyright
  {
    NSRect f = [copyrightLabel frame];
    y -= NSHeight(f);
    f.origin.x = cx - NSWidth(f) / 2.0;
    f.origin.y = y;
    [copyrightLabel setFrame: f];
    [cv addSubview: copyrightLabel];
  }

  // Copyright description
  if (copyrightDescriptionLabel)
    {
      y -= gap;
      NSRect f = [copyrightDescriptionLabel frame];
      y -= NSHeight(f);
      f.origin.x = cx - NSWidth(f) / 2.0;
      f.origin.y = y;
      [copyrightDescriptionLabel setFrame: f];
      [cv addSubview: copyrightDescriptionLabel];
    }

  y -= gap;

  // Theme
  {
    NSRect f = [themeLabel frame];
    y -= NSHeight(f);
    f.origin.x = cx - NSWidth(f) / 2.0;
    f.origin.y = y;
    [themeLabel setFrame: f];
    [cv addSubview: themeLabel];
  }

  [result setBackgroundColor: [NSColor windowBackgroundColor]];
  [cv setNeedsDisplay: YES];
  [result center];

  return result;
}

- (void)eau_setTitle:(NSString *)title
{
  /* NSApplication titles the standard About/Info panel with the localized
   * "Info" string, but it resolves from the GNUstep framework bundle, not
   * from the app's own bundle (which has no lproj entry for it).  Comparing
   * against the app's own NSLocalizedString(@"Info") therefore only ever
   * matched the English "Info" and left the panel untranslated on other
   * locales (e.g. "Information" in German).  Compare against the framework's
   * resolution so the rename to "About <App>" applies on every locale; the
   * literal "Info" fallback covers resolutions that return the raw key. */
  NSBundle *guiBundle = [NSBundle bundleForClass: [GSInfoPanel class]];
  NSString *frameworkInfo = [guiBundle localizedStringForKey: @"Info"
                                                       value: @"Info"
                                                       table: nil];
  if ([title isEqualToString: frameworkInfo]
      || [title isEqualToString: @"Info"])
    {
      NSString *appName = [[NSProcessInfo processInfo] processName];
      title = [NSString stringWithFormat: _(@"About %@"), appName];
    }
  [self eau_setTitle: title];
}

- (void)_eau_openURL:(id)sender
{
  NSString *urlStr = objc_getAssociatedObject(sender, &kEauAppNameKey);
  if ([urlStr length] > 0)
    {
      // Extract the actual URL if it's embedded in display text
      // (e.g. "See http://example.org" → "http://example.org")
      NSRange r = [urlStr rangeOfString: @"http"];
      if (r.location != NSNotFound)
        urlStr = [urlStr substringFromIndex: r.location];
      // Launch the URL via the system's "open" command (non-blocking)
      NSTask *task = AUTORELEASE([NSTask new]);
      [task setLaunchPath: @"/usr/bin/env"];
      [task setArguments: [NSArray arrayWithObjects: @"open", urlStr, nil]];
      [task launch];
    }
}

@end
