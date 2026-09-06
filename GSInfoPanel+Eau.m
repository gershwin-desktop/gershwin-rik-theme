#import "GSInfoPanel+Eau.h"
#import "Eau.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSRegularExpression.h>
#import <Foundation/NSURL.h>

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
#import <AppKit/NSWorkspace.h>

#import <GNUstepGUI/GSTheme.h>

#import "AppearanceMetrics.h"

#import <math.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/* Dominant hue of an image: circular mean of the pixel hues, weighted by
 * saturation (and alpha), so near-gray pixels - which have an arbitrary
 * hue - do not skew the result.  Returns -1 when the image has no
 * meaningful color (all gray/transparent); outSaturation then receives the
 * mean saturation of the colored pixels anyway (0 for a gray image), so
 * callers can also use it as a saturation cap. */
/* RGB<->HSV helpers operating on 0..1 components, used by the ribbon
 * recoloring so we can touch decoded pixels without an offscreen context. */
static void EauRGBtoHSV(CGFloat r, CGFloat g, CGFloat b,
                        CGFloat *h, CGFloat *s, CGFloat *v)
{
  CGFloat max = r > g ? r : g;
  if (b > max) max = b;
  CGFloat min = r < g ? r : g;
  if (b < min) min = b;
  *v = max;
  CGFloat d = max - min;
  if (d <= 0.00001)
    {
      *h = 0.0;
      *s = 0.0;
      return;
    }
  *s = (max <= 0.0) ? 0.0 : d / max;
  if (max == r)
    *h = (g - b) / d;
  else if (max == g)
    *h = 2.0 + (b - r) / d;
  else
    *h = 4.0 + (r - g) / d;
  *h /= 6.0;
  if (*h < 0.0) *h += 1.0;
}

static void EauHSVtoRGB(CGFloat h, CGFloat s, CGFloat v,
                        CGFloat *r, CGFloat *g, CGFloat *b)
{
  if (s <= 0.0)
    {
      *r = *g = *b = v;
      return;
    }
  h = fmod(h, 1.0);
  if (h < 0.0) h += 1.0;
  CGFloat f = h * 6.0;
  NSInteger i = (NSInteger)f;
  CGFloat fr = f - (CGFloat)i;
  CGFloat p = v * (1.0 - s);
  CGFloat q = v * (1.0 - s * fr);
  CGFloat t = v * (1.0 - s * (1.0 - fr));
  switch (i % 6)
    {
      case 0: *r = v; *g = t; *b = p; break;
      case 1: *r = q; *g = v; *b = p; break;
      case 2: *r = p; *g = v; *b = t; break;
      case 3: *r = p; *g = q; *b = v; break;
      case 4: *r = t; *g = p; *b = v; break;
      default: *r = v; *g = p; *b = q; break;
    }
}

static CGFloat EauDominantImageHue(NSImage *image, CGFloat *outSaturation)
{
  if (outSaturation != NULL)
    *outSaturation = 0.0;
  if (image == nil)
    return -1.0;

  /* Work directly on the decoded bitmap bytes instead of drawing the image
   * into an offscreen context.  lockFocus triggers backend/context setup the
   * first time it is used, which both slows this (synchronous) About-panel
   * build and can delay the window mapping past the window manager's
   * focus-stealing guard.  Reading the already-decoded pixels is instant. */
  NSBitmapImageRep *rep = nil;
  for (NSImageRep *r in [image representations])
    {
      if ([r isKindOfClass: [NSBitmapImageRep class]])
        {
          rep = (NSBitmapImageRep *)r;
          break;
        }
    }
  if (rep == nil)
    return -1.0;

  NSInteger w = [rep pixelsWide];
  NSInteger h = [rep pixelsHigh];
  NSInteger spp = [rep samplesPerPixel];
  NSInteger bps = [rep bitsPerSample];
  unsigned char *data = [rep bitmapData];
  if (data == NULL || bps != 8 || (spp != 3 && spp != 4))
    return -1.0;

  BOOL alpha = [rep hasAlpha];
  double x = 0.0, y = 0.0, satWeightSum = 0.0, satSum = 0.0;
  NSInteger rowBytes = [rep bytesPerRow];

  /* Sample at a fixed cost regardless of icon size: a 1024px icon would
   * otherwise mean a million-pixel loop on the (synchronous) first About
   * build.  Step so we inspect at most ~64x64 representative pixels. */
  NSInteger step = (NSInteger)ceil((double)MAX(w, h) / 64.0);
  if (step < 1) step = 1;

  for (NSInteger py = 0; py < h; py += step)
    {
      unsigned char *row = data + py * rowBytes;
      for (NSInteger px = 0; px < w; px += step)
        {
          unsigned char *p = row + px * spp;
          CGFloat r = p[0] / 255.0;
          CGFloat g = p[1] / 255.0;
          CGFloat b = p[2] / 255.0;
          CGFloat a = alpha ? p[3] / 255.0 : 1.0;
          if (a < 0.5)
            continue;
          CGFloat hue, sat, bri;
          EauRGBtoHSV(r, g, b, &hue, &sat, &bri);
          if (sat < 0.25 || bri < 0.15)
            continue;
          double wgt = (double)sat * (double)a;
          x += cos(hue * 2.0 * M_PI) * wgt;
          y += sin(hue * 2.0 * M_PI) * wgt;
          satWeightSum += wgt;
          satSum += (double)sat * wgt;
        }
    }

  if (outSaturation != NULL && satWeightSum > 0.0)
    *outSaturation = (CGFloat)(satSum / satWeightSum);

  if (x == 0.0 && y == 0.0)
    return -1.0;

  CGFloat hue = (CGFloat) (atan2(y, x) / (2.0 * M_PI));
  if (hue < 0.0)
    hue += 1.0;
  return hue;
}

/* Recolors an image: every saturated pixel's hue is rotated to targetHue
 * (a negative targetHue desaturates completely, for gray icons), keeping
 * brightness and alpha.  Saturation is capped at maxSaturation - it is
 * only ever reduced, never boosted - and unsaturated pixels (the
 * white/gray parts of the ribbon and its transparent corners) are left
 * untouched, so the shading survives the shift. */
static NSImage *EauImageByShiftingHue(NSImage *image, CGFloat targetHue,
                                      CGFloat maxSaturation)
{
  if (image == nil)
    return image;

  /* Recolor in place on the decoded bitmap bytes.  This avoids lockFocus
   * (and the first-use backend setup it triggers), so building the About
   * panel stays cheap and the window maps promptly on the first open. */
  NSBitmapImageRep *rep = nil;
  for (NSImageRep *r in [image representations])
    {
      if ([r isKindOfClass: [NSBitmapImageRep class]])
        {
          rep = (NSBitmapImageRep *)r;
          break;
        }
    }
  if (rep == nil)
    return image;

  NSInteger w = [rep pixelsWide];
  NSInteger h = [rep pixelsHigh];
  NSInteger spp = [rep samplesPerPixel];
  NSInteger bps = [rep bitsPerSample];
  unsigned char *data = [rep bitmapData];
  if (data == NULL || bps != 8 || (spp != 3 && spp != 4))
    return image;

  BOOL alpha = [rep hasAlpha];
  NSInteger rowBytes = [rep bytesPerRow];

  for (NSInteger py = 0; py < h; py++)
    {
      unsigned char *row = data + py * rowBytes;
      for (NSInteger px = 0; px < w; px++)
        {
          unsigned char *p = row + px * spp;
          CGFloat r = p[0] / 255.0;
          CGFloat g = p[1] / 255.0;
          CGFloat b = p[2] / 255.0;
          CGFloat a = alpha ? p[3] / 255.0 : 1.0;
          if (a < 0.05)
            continue;
          CGFloat hue, sat, bri;
          EauRGBtoHSV(r, g, b, &hue, &sat, &bri);
          if (sat < 0.15)
            continue;
          if (targetHue >= 0.0)
            hue = targetHue;
          if (maxSaturation >= 0.0 && sat > maxSaturation)
            sat = maxSaturation;
          EauHSVtoRGB(hue, sat, bri, &r, &g, &b);
          p[0] = (unsigned char)(r * 255.0);
          p[1] = (unsigned char)(g * 255.0);
          p[2] = (unsigned char)(b * 255.0);
        }
    }

  NSImage *out = [[NSImage alloc] initWithSize: [image size]];
  [out addRepresentation: rep];
  return out;
}

// Replace "Copyright (c)", "Copyright (C)", bare "(c)"/"(C)" and
// "(tm)"/"(TM)" (and case variations) markers with the unicode copyright
// and trademark symbols.
static NSString *
_eau_symbolizeMarks(NSString *text)
{
  if ([text length] == 0)
    return text;

  static NSRegularExpression *copyrightRe = nil;
  static NSRegularExpression *cRe = nil;
  static NSRegularExpression *tmRe = nil;

  if (copyrightRe == nil)
    {
      copyrightRe = [NSRegularExpression regularExpressionWithPattern:
        @"Copyright\\s*\\((c|C)\\)"
        options: NSRegularExpressionCaseInsensitive
        error: NULL];
      cRe = [NSRegularExpression regularExpressionWithPattern:
        @"\\((c|C)\\)" options: 0 error: NULL];
      tmRe = [NSRegularExpression regularExpressionWithPattern:
        @"\\((t|T)(m|M)\\)" options: 0 error: NULL];
    }

  text = [copyrightRe stringByReplacingMatchesInString: text
    options: 0 range: NSMakeRange(0, [text length])
    withTemplate: @"\u00A9"];
  text = [cRe stringByReplacingMatchesInString: text
    options: 0 range: NSMakeRange(0, [text length])
    withTemplate: @"\u00A9"];
  text = [tmRe stringByReplacingMatchesInString: text
    options: 0 range: NSMakeRange(0, [text length])
    withTemplate: @"\u2122"];
  return text;
}

// ---------------------------------------------------------------------------
// URL button - shows pointing-hand cursor on hover, no highlight
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

/* The About/Info panel must appear on top the very first time it is opened.
 * NSApplication shows it with a plain -orderFront:, which on X11 lets the
 * window manager's focus-stealing prevention refuse to raise a window that is
 * mapped late (the first build does synchronous work) and leaves it below the
 * key window.  Activate the app and make the panel key+front so the window
 * manager raises it above the app on every open, first try included. */
- (void)orderFront:(id)sender
{
  [NSApp activateIgnoringOtherApps: YES];
  [self makeKeyAndOrderFront: sender];
}

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

  @try
    {
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
          else if ([val hasSuffix: @": "] || [val hasSuffix: @":"])
            {
              // The author title label is localized (e.g. "Authors: ",
              // "Autoren: "), so match it by its trailing colon instead
              // of hard-coding English prefixes.
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
              [tf setStringValue: _eau_symbolizeMarks([tf stringValue])];
              [tf sizeToFit];
            }
          else
            {
              copyrightDescriptionLabel = tf;
              [tf setAlignment: NSCenterTextAlignment];
              [tf setStringValue: _eau_symbolizeMarks([tf stringValue])];
              [tf sizeToFit];
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
              // GNUstep sizeToFit ignores the frame width for wrapping
              // fields, so measure the wrapped size explicitly and cap the
              // width so multi-line text stays within the window.
              {
                NSDictionary *attrs =
                  [NSDictionary dictionaryWithObject: [NSFont systemFontOfSize: 12]
                                              forKey: NSFontAttributeName];
                NSRect wr = [[authorField stringValue]
                  boundingRectWithSize: NSMakeSize(288.0, 10000)
                               options: NSStringDrawingUsesLineFragmentOrigin
                            attributes: attrs];
                [authorField setFrame: NSMakeRect(0, 0,
                                MIN(NSWidth(wr), 288.0), NSHeight(wr))];
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

  // ---- 4b. GitHub ribbon in the top-left corner ----
  // Projects hosted on github.com get the classic "fork me" ribbon; it
  // ships with the theme so showing it never needs network access.  Its
  // hue follows the app icon's dominant hue and its saturation never
  // exceeds the icon's own, so the banner always matches the app it
  // decorates; a gray icon gets a gray banner.
  NSButton *ribbonButton = nil;
  if (urlLabel
      && [[urlLabel stringValue]
            rangeOfString: @"github.com"
                  options: NSCaseInsensitiveSearch].location != NSNotFound)
    {
      /* NSImage imageNamed: only resolves theme images that are listed in
       * the theme's GSThemeImages mapping, which ours is not; load it
       * straight from the theme bundle instead. */
      NSString *path = [[[GSTheme theme] bundle]
                         pathForResource: @"common_ForkMeRibbon"
                                  ofType: @"png"
                             inDirectory: @"ThemeImages"];
      NSImage *ribbon = path ? [[NSImage alloc] initWithContentsOfFile: path]
                             : nil;
       if (ribbon != nil && iconButton != nil)
        {
          @try
            {
              CGFloat iconSaturation = 0.0;
              CGFloat iconHue = EauDominantImageHue([iconButton image],
                                                    &iconSaturation);
              ribbon = EauImageByShiftingHue(ribbon, iconHue, iconSaturation);
            }
          @catch (id ex)
            {
            }
        }
      if (ribbon)
        {
          ribbonButton = AUTORELEASE([_EauURLButton new]);
          [ribbonButton setImage: ribbon];
          /* A fresh button cell defaults to NSNoImage, which would draw
           * neither the image nor show the ribbon at all. */
          [ribbonButton setImagePosition: NSImageOnly];
          [ribbonButton setTitle: @""];
          [ribbonButton setBordered: NO];
          [ribbonButton setFocusRingType: NSFocusRingTypeNone];
          [ribbonButton setRefusesFirstResponder: YES];
          [ribbonButton setTarget: self];
          [ribbonButton setAction: @selector(_eau_openURL:)];
          [ribbonButton setFrameSize: NSMakeSize(149.0, 149.0)];
          objc_setAssociatedObject(ribbonButton, &kEauAppNameKey,
                                   [urlLabel stringValue],
                                   OBJC_ASSOCIATION_COPY);
        }
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

  // Reflow any text fields that exceed the content width (the 360pt
  // window minus the two 36pt margins), so that long text wraps instead
  // of overflowing the window.
  {
    CGFloat cw = 288.0;
    void (^reflow)(NSTextField *) = ^(NSTextField *tf) {
      if (!tf || NSWidth([tf frame]) <= cw) return;
      // GNUstep sizeToFit ignores the frame width for wrapping fields,
      // so measure the wrapped height explicitly.
      NSDictionary *attrs = [NSDictionary dictionaryWithObject: [tf font]
                                                        forKey: NSFontAttributeName];
      NSRect nr = [[tf stringValue] boundingRectWithSize: NSMakeSize(cw, 10000)
                                                 options: NSStringDrawingUsesLineFragmentOrigin
                                              attributes: attrs];
      NSRect f = [tf frame];
      f.size.width = cw;
      f.size.height = NSHeight(nr);
      [tf setFrame: f];
      [[tf cell] setWraps: YES];
      [[tf cell] setScrollable: NO];
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

  // GitHub ribbon, 1:1 and flush into the left edge below the in-window
  // titlebar (Eau draws its decorations inside the content view); added
  // last so it draws over the icon and name rather than being clipped.
  if (ribbonButton)
    {
      NSRect f = [ribbonButton frame];
      f.origin.x = 0.0;
      f.origin.y = totalH - NSHeight(f) - METRICS_TITLEBAR_HEIGHT;
      [ribbonButton setFrame: f];
      [cv addSubview: ribbonButton];
    }

  [result setBackgroundColor: [NSColor windowBackgroundColor]];
  [cv setNeedsDisplay: YES];
  [result center];
    }
  @catch (id ex)
    {
      /* Leave the panel as the original built it; never return a gutted
       * (subview-stripped) window if our restyle throws. */
    }

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
      // Open the URL the GNUstep-native way, through the workspace, so it
      // goes to the same handler as every other URL in the desktop.
      NSURL *url = [NSURL URLWithString: urlStr];
      if (url != nil)
        [[NSWorkspace sharedWorkspace] openURL: url];
    }
}

@end
