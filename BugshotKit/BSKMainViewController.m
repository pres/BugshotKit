//  BSKMainViewController.m
//  See included LICENSE file for the (MIT) license.
//  Created by Marco Arment on 1/17/14.

#import "BSKMainViewController.h"
#import "BugshotKit.h"
#import "BSKLogViewController.h"
#import "BSKScreenshotViewController.h"
#import "BSKToggleButton.h"
#import <QuartzCore/QuartzCore.h>
#import <unistd.h>
#include <sys/types.h>
#include <sys/sysctl.h>

static UIImage *rotateIfNeeded(UIImage *src);

@interface BSKMainViewController ()
@property (nonatomic) BSKToggleButton *includeScreenshotToggle;
@property (nonatomic) BSKToggleButton *includeLogToggle;
@property (nonatomic) UIButton *screenshotView;
@property (nonatomic) UIImageView *screenshotAccessoryView;
@property (nonatomic) UIButton *consoleView;
@property (nonatomic) UIImageView *consoleAccessoryView;
@property (nonatomic) UILabel *screenshotLabel;
@property (nonatomic) UILabel *consoleLabel;
@end

@implementation BSKMainViewController

- (BOOL)shouldAutorotate { return NO; }

- (instancetype)init
{
    if ( (self = [super initWithStyle:UITableViewStyleGrouped]) ) {
        [BugshotKit.sharedManager addObserver:self forKeyPath:@"annotatedImage" options:0 context:NULL];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateLiveLog:) name:BSKNewLogMessageNotification object:nil];

        self.title = @"Bugshot";
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelButtonTapped:)];
        self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    }
    return self;
}

- (void)dealloc
{
    [BugshotKit.sharedManager removeObserver:self forKeyPath:@"annotatedImage"];
    [NSNotificationCenter.defaultCenter removeObserver:self name:BSKNewLogMessageNotification object:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    CGSize chevronSize = CGSizeMake(15, 30);
    UIImage *chevronImage = BSKImageWithDrawing(chevronSize, ^{
        CGRect chevronBounds = CGRectMake(0, 0, chevronSize.width, chevronSize.height);
        chevronBounds = CGRectInset(chevronBounds, 3.0f, 6.0f);
        
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(chevronBounds.origin.x, chevronBounds.origin.y)];
        [path addLineToPoint:CGPointMake(chevronBounds.origin.x + chevronBounds.size.width, chevronBounds.origin.y + (chevronBounds.size.height / 2.0f))];
        [path addLineToPoint:CGPointMake(chevronBounds.origin.x, chevronBounds.origin.y + chevronBounds.size.height)];
        [path setLineWidth:ceilf((float)chevronSize.width * 0.2f)];
        [BugshotKit.sharedManager.toggleOffColor setStroke];
        [path stroke];
    });

    UIImage *screenshotImage = (BugshotKit.sharedManager.annotatedImage ?: BugshotKit.sharedManager.snapshotImage);

    CGFloat maxHeaderHeight =
        UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? (UIInterfaceOrientationIsPortrait(self.interfaceOrientation) ? 570 : 480) :
        UIInterfaceOrientationIsPortrait(self.interfaceOrientation) ? (UIScreen.mainScreen.bounds.size.height < 568 ? 300 : 340) : 220
    ;
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, maxHeaderHeight)];
    
    UIView *screenshotContainer = [UIView new];
    screenshotContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.screenshotLabel = [UILabel new];
    self.screenshotLabel.text = @"SCREENSHOT";
    self.screenshotLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    self.screenshotLabel.textColor = BugshotKit.sharedManager.annotationFillColor;
    self.screenshotLabel.textAlignment = NSTextAlignmentCenter;
    self.screenshotLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [screenshotContainer addSubview:self.screenshotLabel];
    
    CGFloat toggleWidth = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone && UIInterfaceOrientationIsLandscape(self.interfaceOrientation) ? 44 : 74;
    
    self.includeScreenshotToggle = [[BSKToggleButton alloc] initWithFrame:CGRectMake(0, 0, toggleWidth, toggleWidth)];
    self.includeScreenshotToggle.on = YES;
    [self.includeScreenshotToggle addTarget:self action:@selector(includeScreenshotToggled:) forControlEvents:UIControlEventValueChanged];
    self.includeScreenshotToggle.translatesAutoresizingMaskIntoConstraints = NO;
    self.includeScreenshotToggle.accessibilityLabel = @"Include screenshot";
    [screenshotContainer addSubview:self.includeScreenshotToggle];
    
    self.screenshotView = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.screenshotView addTarget:self action:@selector(openScreenshotEditor:) forControlEvents:UIControlEventTouchUpInside];
    [self.screenshotView setBackgroundImage:screenshotImage forState:UIControlStateNormal];
    self.screenshotView.translatesAutoresizingMaskIntoConstraints = NO;
    self.screenshotView.layer.borderColor = BugshotKit.sharedManager.annotationFillColor.CGColor;
    self.screenshotView.layer.borderWidth = 1.0f;
    self.screenshotView.accessibilityLabel = @"Annotate screenshot";
    [screenshotContainer addSubview:self.screenshotView];
    
    self.screenshotAccessoryView = [[UIImageView alloc] initWithImage:chevronImage];
    self.screenshotAccessoryView.translatesAutoresizingMaskIntoConstraints = NO;
    self.screenshotAccessoryView.isAccessibilityElement = NO;
    [screenshotContainer addSubview:self.screenshotAccessoryView];
    
    void (^layoutScreenshotUnit)(UIView *container, NSDictionary *views) = ^(UIView *container, NSDictionary *views){
        NSDictionary *metrics = @{
            @"aw" : @(chevronSize.width), @"ah" : @(chevronSize.height), @"apad" : @(chevronSize.width + 5.0f),
            @"lfont" : @( ((UILabel *)views[@"label"]).font.pointSize ),
            @"padImageHeight" : @(384)
        };
    
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-15-[label(>=lfont)]-5-[image]-15-[toggle]" options:0 metrics:metrics views:views]];
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"[accessory(==aw)]|" options:0 metrics:metrics views:views]];
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[accessory(==ah)]" options:0 metrics:metrics views:views]];
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|[label]|" options:0 metrics:nil views:views]];
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|-apad-[image]-apad-|" options:0 metrics:metrics views:views]];
        [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[toggle]-15-|" options:0 metrics:nil views:views]];

        // horizontally center toggle
        [container addConstraint:[NSLayoutConstraint
            constraintWithItem:views[@"toggle"] attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:container attribute:NSLayoutAttributeCenterX multiplier:1 constant:0
        ]];
        
        // vertically center accessory to image
        [container addConstraint:[NSLayoutConstraint
            constraintWithItem:views[@"accessory"] attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:views[@"image"] attribute:NSLayoutAttributeCenterY multiplier:1 constant:0
        ]];
        
        // toggle is always square
        [container addConstraint:[NSLayoutConstraint
            constraintWithItem:views[@"toggle"] attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:views[@"toggle"] attribute:NSLayoutAttributeWidth multiplier:1 constant:0
        ]];
    };
    
    layoutScreenshotUnit(screenshotContainer, @{
        @"label" : self.screenshotLabel,
        @"image" : self.screenshotView,
        @"accessory" : self.screenshotAccessoryView,
        @"toggle" : self.includeScreenshotToggle
    });

    [headerView addSubview:screenshotContainer];
    
    [headerView addConstraint:[NSLayoutConstraint
        constraintWithItem:screenshotContainer attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationLessThanOrEqual toItem:headerView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0
    ]];

    [headerView sizeToFit];
    self.tableView.tableHeaderView = headerView;
}

- (void)openScreenshotEditor:(id)sender
{
    [self.navigationController pushViewController:[[BSKScreenshotViewController alloc] initWithImage:BugshotKit.sharedManager.snapshotImage annotations:BugshotKit.sharedManager.annotations] animated:YES];
}

- (void)includeScreenshotToggled:(id)sender
{
    if (self.includeScreenshotToggle.on) {
        self.screenshotLabel.textColor = BugshotKit.sharedManager.annotationFillColor;
        self.screenshotView.layer.borderColor = BugshotKit.sharedManager.annotationFillColor.CGColor;
    } else {
        self.screenshotLabel.textColor = BugshotKit.sharedManager.toggleOffColor;
        self.screenshotView.layer.borderColor = BugshotKit.sharedManager.toggleOffColor.CGColor;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (! self.isViewLoaded) return;
    [self.screenshotView setBackgroundImage:(BugshotKit.sharedManager.annotatedImage ?: BugshotKit.sharedManager.snapshotImage) forState:UIControlStateNormal];
}

- (void)cancelButtonTapped:(id)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:^{
        if (self.delegate) [self.delegate mainViewControllerDidClose:self];
    }];
}

- (void)consoleButtonTapped:(id)sender
{
    [self.navigationController pushViewController:[[BSKLogViewController alloc] init] animated:YES];
}

- (void)sendButtonTapped:(id)sender
{
    if (self.includeLogToggle.on) {
        [BugshotKit.sharedManager currentConsoleLogWithDateStamps:YES withCompletion:^(NSString *result) {
            [self sendButtonTappedWithLog:result];
        }];
    }
    else {
        [self sendButtonTappedWithLog:nil];
    }
}

- (void)sendButtonTappedWithLog:(NSString *)log
{
    UIImage *screenshot = self.includeScreenshotToggle.on ? (BugshotKit.sharedManager.annotatedImage ?: BugshotKit.sharedManager.snapshotImage) : nil;
    if (log && ! log.length) log = nil;
    
    NSString *appNameString = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    NSString *appVersionString = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];

    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0); 
    char *name = malloc(size);
    sysctlbyname("hw.machine", name, &size, NULL, 0);
    NSString *modelIdentifier = [NSString stringWithCString:name encoding:NSUTF8StringEncoding];
    free(name);

    NSDictionary *userInfo = @{
        @"appName" : appNameString,
        @"appVersion" : appVersionString,
        @"systemVersion" : UIDevice.currentDevice.systemVersion,
        @"deviceModel" : modelIdentifier,
    };
    
    NSDictionary *extraUserInfo = BugshotKit.sharedManager.extraInfoBlock ? BugshotKit.sharedManager.extraInfoBlock() : nil;
    if (extraUserInfo) {
        userInfo = userInfo.mutableCopy;
        [(NSMutableDictionary *)userInfo addEntriesFromDictionary:extraUserInfo];
    };
    
    MFMailComposeViewController *mf = [MFMailComposeViewController canSendMail] ? [[MFMailComposeViewController alloc] init] : nil;
    if (! mf) {
        NSString *msg = [NSString stringWithFormat:@"Mail is not configured on your %@.", UIDevice.currentDevice.localizedModel];
        [[[UIAlertView alloc] initWithTitle:@"Cannot Send Mail" message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return;
    }
    
    mf.toRecipients = [BugshotKit.sharedManager.destinationEmailAddress componentsSeparatedByString:@","];
    mf.subject = BugshotKit.sharedManager.emailSubjectBlock ? BugshotKit.sharedManager.emailSubjectBlock(userInfo) : [NSString stringWithFormat:@"%@ %@ Feedback", appNameString, appVersionString];
    [mf setMessageBody:BugshotKit.sharedManager.emailBodyBlock ? BugshotKit.sharedManager.emailBodyBlock(userInfo) : nil isHTML:NO];

    if (screenshot) [mf addAttachmentData:UIImagePNGRepresentation(rotateIfNeeded(screenshot)) mimeType:@"image/png" fileName:@"screenshot.png"];
    if(BugshotKit.sharedManager.mailComposeCustomizeBlock) BugshotKit.sharedManager.mailComposeCustomizeBlock(mf);
    
    mf.mailComposeDelegate = self;
    [self presentViewController:mf animated:YES completion:NULL];
}

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    [self dismissViewControllerAnimated:YES completion:^{
        if (result == MFMailComposeResultSaved || result == MFMailComposeResultSent) [self cancelButtonTapped:nil];
    }];
}

#pragma mark - Table junk

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = BugshotKit.sharedManager.annotationFillColor;
    cell.textLabel.text = @"Compose Email…";

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self sendButtonTapped:nil];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Live console image

- (void)updateLiveLog:(NSNotification *)n
{
    if (! self.isViewLoaded) return;
    [BugshotKit.sharedManager consoleImageWithSize:self.consoleView.bounds.size fontSize:7 emptyBottomLine:NO withCompletion:^(UIImage *image) {
        [self.consoleView setBackgroundImage:image forState:UIControlStateNormal];
    }];
}

@end


// By Matteo Gavagnin on 21/01/14.
static UIImage *rotateIfNeeded(UIImage *src)
{
    if (src.imageOrientation == UIImageOrientationDown && src.size.width < src.size.height) {
        UIGraphicsBeginImageContext(src.size);
        [src drawAtPoint:CGPointMake(0, 0)];
        return UIGraphicsGetImageFromCurrentImageContext();
    } else if ((src.imageOrientation == UIImageOrientationLeft || src.imageOrientation == UIImageOrientationRight) && src.size.width > src.size.height) {
        UIGraphicsBeginImageContext(src.size);
        [src drawAtPoint:CGPointMake(0, 0)];
        return UIGraphicsGetImageFromCurrentImageContext();
    } else {
        return src;
    }
}
