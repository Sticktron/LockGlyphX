//
//  LockGlyphXThemeController.mm
//  Theme Chooser
//
//  (c)2017 evilgoldfish
//
//  feat. @sticktron
//

#import "Common.h"
#import <Preferences/PSViewController.h>


#define kMesaThumbnailPath @"/Applications/StoreKitUIService.app/MesaGlyph.png"

#define kThumbnailTag 	1
#define kTitleTag 		2
#define kSoundTag 		3


@implementation UIImage (LockGlyphX)
+ (UIImage *)imageFromImageView:(UIImageView *)imageView {
	UIGraphicsBeginImageContextWithOptions(imageView.frame.size, NO, 0); // use screen scale factor
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextRotateCTM(context, 2 * M_PI);
    [imageView.layer renderInContext:context];
    UIImage *image =  UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}
@end


@interface LockGlyphXThemeController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *themes;
@property (nonatomic, strong) NSString *selectedTheme;
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, strong) NSCache *imageCache;
@property (nonatomic, strong) NSIndexPath *checkedIndexPath;
@end

@implementation LockGlyphXThemeController
- (instancetype)init {
	self = [super init];
	if (self) {
		self.title = @"Themes";
		
		_imageCache = [[NSCache alloc] init];
		_queue = [[NSOperationQueue alloc] init];
		_queue.maxConcurrentOperationCount = 4;
		
		// check prefs for selected theme
		CFPreferencesAppSynchronize(kPrefsAppID);
		CFPropertyListRef value = CFPreferencesCopyAppValue(kPrefsCurrentThemeKey, kPrefsAppID);
		_selectedTheme = (value) ? (NSString *)CFBridgingRelease(value) : kDefaultThemeBundle;
	}
	return self;
}
- (void)viewDidLoad {
	[super viewDidLoad];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
	self.tableView.delegate = self;
	self.tableView.dataSource = self;
	self.tableView.rowHeight = 60.0f;
	[self.view addSubview:self.tableView];
}
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	
	// tint navbar
	self.navigationController.navigationController.navigationBar.tintColor = kTintColor;
	
	[self updateThemeList];
}
- (void)viewWillDisappear:(BOOL)animated {
	// un-tint navbar
	self.navigationController.navigationController.navigationBar.tintColor = nil;

	// empty the thumbnail cache
	[self.imageCache removeAllObjects];

	[super viewWillDisappear:animated];
}
- (void)updateThemeList {
	// create the theme list, starting with the default theme
	NSDictionary *defaultTheme = @{ @"bundle":kDefaultThemeBundle, @"name":kDefaultThemeName, @"hasSound":@YES };
	NSMutableArray *themes = [NSMutableArray arrayWithArray:@[ defaultTheme ]];
	
	NSMutableArray *folders = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:kThemePath error:nil] mutableCopy];
    for (int i = 0; i < folders.count; i++) {
    	NSString *path = [folders objectAtIndex:i];
		if (![path isEqualToString:kDefaultThemeBundle]) { // skip the default theme, it's already in the list
			NSString *name = [path stringByReplacingOccurrencesOfString:@".bundle" withString:@""];
			BOOL hasSound = [[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@/SuccessSound.wav", kThemePath, path]];
			[themes addObject:@{ @"bundle":path, @"name":name, @"hasSound":[NSNumber numberWithBool:hasSound] }];
		}
    }
	self.themes = themes;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.themes.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CustomCellIdentifier = @"CustomCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CustomCellIdentifier];
	
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CustomCellIdentifier];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryType = UITableViewCellAccessoryNone;
		
		// thumbnail
		UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(15, 5, 48, 48)];
		imageView.opaque = YES;
		imageView.backgroundColor = UIColor.whiteColor;
		imageView.contentMode = UIViewContentModeScaleAspectFit;
		imageView.tag = kThumbnailTag;
		[cell.contentView addSubview:imageView];
		
		// title
		UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(78, 20, cell.contentView.bounds.size.width - 78, 20)];
		titleLabel.opaque = YES;
		titleLabel.font = [UIFont systemFontOfSize:14];
		titleLabel.textColor = UIColor.blackColor;
		titleLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
		titleLabel.tag = kTitleTag;
		[cell.contentView addSubview:titleLabel];
		
		// sound icon
		UIImage *soundIcon = [[UIImage alloc] initWithContentsOfFile:[NSString stringWithFormat:@"%@/sound.png", kPrefsBundlePath]];
		UIImageView *soundIconView = [[UIImageView alloc] initWithImage:soundIcon];
		soundIconView.frame = (CGRect){{80, 43}, soundIconView.frame.size};
		soundIconView.tag = kSoundTag;
		soundIconView.hidden = YES;
		[cell.contentView addSubview:soundIconView];
	}
	
	// reset and populate cell...
	
	UILabel *titleLabel = (UILabel *)[cell.contentView viewWithTag:kTitleTag];
	UIImageView *imageView = (UIImageView *)[cell.contentView viewWithTag:kThumbnailTag];
	UILabel *soundIconView = (UILabel *)[cell.contentView viewWithTag:kSoundTag];
		
	titleLabel.text = nil;
	imageView.image = nil;
	soundIconView.hidden = YES;
	
	NSDictionary *themeInfo = self.themes[indexPath.row];
	titleLabel.text = themeInfo[@"name"];
	if (themeInfo[@"hasSound"] && [themeInfo[@"hasSound"] boolValue]) soundIconView.hidden = NO;
	
	// get thumbnail from cache, or create and cache new one
	NSString *path;
	if ([themeInfo[@"name"] isEqualToString:kDefaultThemeName]) {
		path = kMesaThumbnailPath;
	} else {
		path = [NSString stringWithFormat:@"%@/%@/IdleImage.png", kThemePath, themeInfo[@"bundle"]];
	}
	UIImage *thumbnail = [self.imageCache objectForKey:path];
	if (thumbnail) {
		imageView.image = thumbnail;
	} else {
		// image is not yet cached, cache it now
		UIImage *image = [UIImage imageWithContentsOfFile:path];
		if (image) {
			// Bake a CALayer shadow into the thumbnail image,
			// using a temporary ImageView.
			UIImageView *dummyView = [[UIImageView alloc] initWithImage:image];
			dummyView.contentMode = UIViewContentModeCenter;
			dummyView.layer.shadowOffset = CGSizeMake(0, 1);
			dummyView.layer.shadowRadius = 1;
			dummyView.layer.shadowColor = UIColor.blackColor.CGColor;
			dummyView.layer.shadowOpacity = 0.4;

			// add some padding for the shadow
			CGRect frame = dummyView.frame;
			frame.size.width += 4;
			frame.size.height += 4;
			dummyView.frame = frame;
			
			image = [UIImage imageFromImageView:dummyView];
			[self.imageCache setObject:image forKey:path];
			
			imageView.image = image;
		}
	}
	
	// do we know which row should be checked?
	if (!self.checkedIndexPath) {
		// not yet; is it this row?
		if ([themeInfo[@"bundle"] isEqualToString:self.selectedTheme]) {
			self.checkedIndexPath = indexPath;
		}
	}
	
	if ([indexPath isEqual:self.checkedIndexPath]) {
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	} else {
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
	
	return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	if (cell.accessoryType == UITableViewCellAccessoryCheckmark) {
		// cell is already selected
	} else {
		// un-check previously checked cell
		UITableViewCell *oldCell = [tableView cellForRowAtIndexPath:self.checkedIndexPath];
		oldCell.accessoryType = UITableViewCellAccessoryNone;
		
		// check this cell
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
		self.checkedIndexPath = indexPath;
		
		// get the image info
		NSDictionary *themeInfo;
		themeInfo = self.themes[indexPath.row];
		
		// save selection to prefs
		self.selectedTheme = themeInfo[@"bundle"];
		CFPreferencesSetAppValue(kPrefsCurrentThemeKey, (CFStringRef)self.selectedTheme, kPrefsAppID);
		CFPreferencesAppSynchronize(kPrefsAppID);
		
		// notify tweak
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kSettingsChangedNotification, NULL, NULL, true);
	}
}
- (void)didReceiveMemoryWarning {
	[self.imageCache removeAllObjects];
	[super didReceiveMemoryWarning];
}
@end
