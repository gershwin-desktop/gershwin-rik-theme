#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Eau.h"

// Category on NSFont used for method swizzling
@interface NSFont (EauSwizzling)
+ (NSFont *)eau_menuBarFontOfSize:(CGFloat)fontSize;
+ (NSFont *)eau_menuFontOfSize:(CGFloat)fontSize;
+ (NSFont *)eau_systemFontOfSize:(CGFloat)fontSize;
+ (NSFont *)eau_boldSystemFontOfSize:(CGFloat)fontSize;
+ (NSFont *)eau_controlContentFontOfSize:(CGFloat)fontSize;
+ (NSFont *)eau_userFontOfSize:(CGFloat)fontSize;
+ (NSFont *)eau_userFixedPitchFontOfSize:(CGFloat)fontSize;
+ (NSFont *)eau_titleBarFontOfSize:(CGFloat)fontSize;
+ (NSFont *)eau_fontWithName:(NSString *)name size:(CGFloat)size;
+ (NSFont *)eau_fontOrDefault:(NSFont *)font size:(CGFloat)size;
@end

@implementation NSFont (EauSwizzling)

// GNUstep resolves the "system font" to a fixed family name such as
// Helvetica. On hosts where fontconfig cannot map that name the resulting
// NSFont object has no glyphs and text drawing fails with "Glyph generation
// with no font".  We make text rendering resilient: whenever the resolved
// font references a family that is not actually available on this system, we
// log a warning and substitute any available sans-serif family instead.

// Memoized list of available font families.  The fontconfig family set does
// not change during a run, and re-enumerating it on every call is expensive:
// building a menu creates one NSMenuItemCell per item and each one resolves
// its font, so without memoizing, a menu rebuild spends its time in
// fontconfig (FcFontSort/FcFontSetSort) instead of drawing - the source of
// Menu.app's repeated CPU bursts while its menu bar is rebuilt.
static NSArray *EauFontFamilies(void)
{
  static NSArray *families = nil;
  if (families == nil)
    families = [[NSFontManager sharedFontManager] availableFontFamilies];
  return families;
}

static NSString *EauAvailableFamily(void)
{
  static NSArray *order = nil;
  if (order == nil)
    order = @[@"Inter", @"Nimbus Sans", @"DejaVu Sans", @"Liberation Sans",
              @"Arial", @"Helvetica", @"Clean", @"Luxi Sans", @"URW Gothic"];

  NSArray *families = EauFontFamilies();
  for (NSString *pattern in order)
    for (NSString *fam in families)
      if ([fam rangeOfString:pattern options:NSCaseInsensitiveSearch]
            .location != NSNotFound)
        return fam;

  return ([families count] > 0) ? [families objectAtIndex:0] : nil;
}

// Memoized substitute font, resolved once per process.  Built via the
// (never swizzled) NSFontManager family API so that building it can never
// re-enter our own swizzled NSFont constructors and cause recursion.
static NSFont *EauFallbackFont(void)
{
  static NSFont *fallback = nil;
  if (fallback == nil)
    {
      NSString *family = EauAvailableFamily();
      if (family != nil)
        fallback = [[NSFontManager sharedFontManager]
                     fontWithFamily:family traits:0 weight:5 size:13.0];
      }
  return fallback;
}

+ (NSFont *)eau_fontOrDefault:(NSFont *)font size:(CGFloat)size
{
  // Cache the resolved font per (family, size): a menu rebuild creates one
  // NSMenuItemCell per item and each one re-runs fontconfig matching
  // (FcFontSort) here, which is what makes Menu.app's CPU spike while menus
  // are rebuilt.  The resolution is deterministic, so caching is safe.
  static NSMutableDictionary *cache = nil;
  if (cache == nil)
    cache = [NSMutableDictionary dictionary];

  NSString *fontFamily = [font familyName];
  NSString *cacheKey = [NSString stringWithFormat: @"%@\v%.1f",
    fontFamily ?: @"", size];
  NSFont *hit = [cache objectForKey: cacheKey];
  if (hit != nil)
    return hit;

  NSFont *resolved = nil;
  // If the resolved font references a family that really exists on the
  // system, keep it (preserves bold/italic and the intended look).
  if (fontFamily != nil)
    {
      NSArray *families = EauFontFamilies();
      for (NSString *fam in families)
        if ([fam isEqualToString:fontFamily])
          {
            NSFontDescriptor *d = [font fontDescriptor];
            resolved = [NSFont fontWithDescriptor: d size: size];
            break;
          }
      // Fall through: family is not reported as available.
    }

  if (resolved == nil)
    {
      // Log once, then fall back to any available sans-serif family so that
      // drawing is guaranteed to work as long as a single font is installed.
      static BOOL warned = NO;
      if (!warned)
        {
          warned = YES;
          NSLog(@"Eau: requested UI font family '%@' is not available on this "
                @"system; using '%@' instead.",
                fontFamily ?: @"(system default)",
                EauAvailableFamily() ?: @"(none)");
        }

      NSString *family = EauAvailableFamily();
      NSFont *usable = (family != nil) ? EauFallbackFont() : nil;
      if (usable == nil && font != nil)
        usable = font;

      NSFontDescriptor *desc = [usable fontDescriptor];
      resolved = [NSFont fontWithDescriptor: desc size: size];
    }

  if (resolved != nil)
    [cache setObject: resolved forKey: cacheKey];
  return resolved;
}

+ (NSFont *)eau_menuBarFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self eau_menuBarFontOfSize:fontSize];
  return [self eau_fontOrDefault:base size:14.0];
}

+ (NSFont *)eau_menuFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self eau_menuFontOfSize:fontSize];
  return [self eau_fontOrDefault:base size:14.0];
}

+ (NSFont *)eau_systemFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self eau_systemFontOfSize:fontSize];
  return [self eau_fontOrDefault:base size:fontSize];
}

+ (NSFont *)eau_boldSystemFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self eau_boldSystemFontOfSize:fontSize];
  return [self eau_fontOrDefault:base size:fontSize];
}

+ (NSFont *)eau_controlContentFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self eau_controlContentFontOfSize:fontSize];
  return [self eau_fontOrDefault:base size:fontSize];
}

+ (NSFont *)eau_userFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self eau_userFontOfSize:fontSize];
  return [self eau_fontOrDefault:base size:fontSize];
}

+ (NSFont *)eau_userFixedPitchFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self eau_userFixedPitchFontOfSize:fontSize];
  return [self eau_fontOrDefault:base size:fontSize];
}

+ (NSFont *)eau_fontWithName:(NSString *)name size:(CGFloat)size
{
  NSFont *base = [self eau_fontWithName:name size:size];
  if (base == nil)
    {
      // The requested font name does not resolve to anything on this system;
      // use the fallback sans-serif font so callers never receive nil.
      NSFont *usable = EauAvailableFamily() ? EauFallbackFont() : nil;
      return usable ?: base;
    }
  return base;
}

+ (NSFont *)eau_titleBarFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self eau_titleBarFontOfSize:fontSize];
  return [self eau_fontOrDefault:base size:fontSize];
}

@end

// Constructor to set up swizzling
__attribute__((constructor))
static void EauSwizzleFonts(void)
{
  Class fontClass = [NSFont class];
  if (fontClass == 0) return;

  /* Collect the selector pairs at runtime (sel_registerName is not a
     compile-time constant, so it cannot appear in a static initializer). */
  SEL origSwaps[] = {
    sel_registerName("menuBarFontOfSize:"),
    sel_registerName("menuFontOfSize:"),
    sel_registerName("systemFontOfSize:"),
    sel_registerName("boldSystemFontOfSize:"),
    sel_registerName("controlContentFontOfSize:"),
    sel_registerName("userFontOfSize:"),
    sel_registerName("userFixedPitchFontOfSize:"),
    sel_registerName("titleBarFontOfSize:"),
    sel_registerName("fontWithName:size:"),
  };
  SEL swzSwaps[] = {
    @selector(eau_menuBarFontOfSize:),
    @selector(eau_menuFontOfSize:),
    @selector(eau_systemFontOfSize:),
    @selector(eau_boldSystemFontOfSize:),
    @selector(eau_controlContentFontOfSize:),
    @selector(eau_userFontOfSize:),
    @selector(eau_userFixedPitchFontOfSize:),
    @selector(eau_titleBarFontOfSize:),
    @selector(eau_fontWithName:size:),
  };
  int count = sizeof(origSwaps) / sizeof(origSwaps[0]);
  for (int i = 0; i < count; i++)
    {
      Method original = class_getClassMethod(fontClass, origSwaps[i]);
      Method swz      = class_getClassMethod(fontClass, swzSwaps[i]);
      if (original != 0 && swz != 0
          && method_getImplementation(original)
               != method_getImplementation(swz))
        method_exchangeImplementations(original, swz);
    }
}