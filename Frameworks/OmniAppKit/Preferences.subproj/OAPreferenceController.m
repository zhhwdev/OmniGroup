// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAPreferenceController.h>

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h> // For AESend
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/NSBundle-OAExtensions.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/NSToolbar-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>
#import <OmniAppKit/OAPreferenceClient.h>
#import <OmniAppKit/OAPreferenceClientRecord.h>
#import "OAPreferencesIconView.h"
#import "OAPreferencesToolbar.h"
#import "OAPreferencesWindow.h"

RCS_ID("$Id$") 

const NSLayoutPriority OAPreferenceClientControlBoxFixedWidthPriority = NSLayoutPriorityFittingSizeCompression + 10;

static OAPreferenceClientRecord *_ClientRecordWithValueForKey(NSArray *records, NSString *key, NSString *value)
{
    OBPRECONDITION(value != nil);
    
    for (OAPreferenceClientRecord *clientRecord in records)
	if ([[clientRecord valueForKey:key] isEqualToString:value])
	    return clientRecord;
    return nil;											\
}

@interface OAPreferenceController ()

// Outlets

@property (nonatomic, retain) IBOutlet NSWindow *window;
@property (nonatomic, assign) IBOutlet NSBox *preferenceBox;
@property (nonatomic, retain) IBOutlet NSView *globalControlsView;;
@property (nonatomic, assign) IBOutlet NSButton *helpButton;
@property (nonatomic, assign) IBOutlet NSButton *returnToOriginalValuesButton;

// Private

- (void)_loadInterface;
- (void)_createShowAllItemsView;
- (void)_setupMultipleToolbar;
- (void)_setupShowAllToolbar;
- (void)_resetWindowTitle;
- (OAPreferenceClient *)_clientForRecord:(OAPreferenceClientRecord *)record;
- (void)_showAllIcons:(id)sender;
- (void)_defaultsDidChange:(NSNotification *)notification;
//
- (NSArray *)_categoryNames;
- (NSArray *)_sortedClientRecords;
+ (void)_registerCategoryName:(NSString *)categoryName localizedName:(NSString *)localizedCategoryName priorityNumber:(NSNumber *)priorityNumber;
+ (NSString *)_localizedCategoryNameForCategoryName:(NSString *)categoryName;
+ (float)_priorityForCategoryName:(NSString *)categoryName;
//
+ (void)_registerClassName:(NSString *)className inCategoryNamed:(NSString *)categoryName description:(NSDictionary *)description;

@end

@interface NSToolbar (KnownPrivateMethods)
- (NSView *)_toolbarView;
- (void)setSelectedItemIdentifier:(NSString *)itemIdentifier; // Panther only
@end

@implementation OAPreferenceController
{
    NSArray *_topLevelObjects;
    
    OAPreferencesWindow *_window;
    NSView *_globalControlsView;
    
    NSView *showAllIconsView; // not to be confused with the "Show All" button
    OAPreferencesIconView *multipleIconView;
    
    NSMutableArray *preferencesIconViews;
    NSMutableDictionary <NSString *, NSMutableArray <OAPreferenceClientRecord *> *> *categoryNamesToClientRecordsArrays;
    
    NSArray <OAPreferenceClientRecord *> *_clientRecords;
    NSMutableDictionary *_clientByRecordIdentifier;
    NSString *_defaultKeySuffix;
    
    OAPreferencesViewStyle viewStyle;
    
    NSToolbar *toolbar;
    NSArray *defaultToolbarItems;
    NSArray *allowedToolbarItems;
    
    OAPreferenceClientRecord *nonretained_currentClientRecord;
    OAPreferenceClient *nonretained_currentClient;
    CGFloat idealWidth;
}

static NSMutableArray *AllClientRecords = nil;
static NSMutableDictionary *LocalizedCategoryNames = nil;
static NSMutableDictionary *CategoryPriorities = nil;
static NSString *windowFrameSaveName = @"Preferences";

+ (void)initialize;
{
    OBINITIALIZE;
    
    AllClientRecords = [[NSMutableArray alloc] init];
    LocalizedCategoryNames = [[NSMutableDictionary alloc] init];
    CategoryPriorities = [[NSMutableDictionary alloc] init];
    
#ifdef DEBUG
    // Debugging aid; if we have this preference, show the pane.  Not doing the whole OF controller thing to get this done; just a simple hack to let the preference panes get registered.
    NSString *paneID = [[NSUserDefaults standardUserDefaults] stringForKey:@"OAPreferenceClientToShowOnLaunch"];
    if (![NSString isEmptyString:paneID])
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_showPane:) userInfo:paneID repeats:NO];
#endif
}

#ifdef DEBUG
+ (void)_showPane:(NSTimer *)timer;
{
    OAPreferenceController *controller = [OAPreferenceController sharedPreferenceController];

    NSString *identifier = [timer userInfo];
    OAPreferenceClientRecord *record = [controller clientRecordWithIdentifier:identifier];
    if (!record) {
        NSLog(@"No pane '%@'", identifier);
        return;
    }
    
    [controller setCurrentClientRecord:record];
    [controller showPreferencesPanel:nil];
}
#endif

// OFBundleRegistryTarget informal protocol

+ (NSString *)overrideNameForCategoryName:(NSString *)categoryName;
{
    return categoryName;
}

+ (NSString *)overrideLocalizedNameForCategoryName:(NSString *)categoryName bundle:(NSBundle *)bundle;
{
    return [bundle localizedStringForKey:categoryName value:@"" table:@"Preferences"];
}

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
    OBPRECONDITION(AllClientRecords != nil); // +initialize
    
    [OFBundledClass createBundledClassWithName:itemName bundle:bundle description:description];

    NSString *categoryName;
    if ((categoryName = [description objectForKey:@"category"]) == nil)
        categoryName = @"UNKNOWN";
        
    categoryName = [self overrideNameForCategoryName:categoryName];
    NSString *localizedCategoryName = [self overrideLocalizedNameForCategoryName:categoryName bundle:bundle];
        
    [self _registerCategoryName:categoryName localizedName:localizedCategoryName priorityNumber:[description objectForKey:@"categoryPriority"]];
    [self _registerClassName:itemName inCategoryNamed:categoryName description:description];
}

+ (OAPreferenceController *)sharedPreferenceController;
{
    static OAPreferenceController *sharedPreferenceController = nil;
    if (sharedPreferenceController == nil)
        sharedPreferenceController = [[self alloc] init];
    
    return sharedPreferenceController;
}

+ (NSArray *)allClientRecords;
{
    return AllClientRecords;
}

+ (OAPreferenceClientRecord *)clientRecordWithShortTitle:(NSString *)shortTitle;
{
    return _ClientRecordWithValueForKey(AllClientRecords, @"shortTitle", shortTitle);
}

+ (OAPreferenceClientRecord *)clientRecordWithIdentifier:(NSString *)identifier;
{
    return _ClientRecordWithValueForKey(AllClientRecords, @"identifier", identifier);
}

// Init and dealloc

- init;
{
    return [self initWithClientRecords:AllClientRecords defaultKeySuffix:nil];
}

- initWithClientRecords:(NSArray *)clientRecords defaultKeySuffix:(NSString *)defaultKeySuffix;
{
    OBPRECONDITION([clientRecords count]);
    
    if (!(self = [super init]))
	return nil;
    
    categoryNamesToClientRecordsArrays = [[NSMutableDictionary alloc] init];
    _clientRecords = [[NSArray alloc] initWithArray:clientRecords];
    _clientByRecordIdentifier = [[NSMutableDictionary alloc] init];
    _defaultKeySuffix = [defaultKeySuffix copy];
    preferencesIconViews = [[NSMutableArray alloc] init];
    
    for (OAPreferenceClientRecord *record in _clientRecords) {
	NSString *categoryName = [record categoryName];
	
	NSMutableArray *categoryClientRecords = [categoryNamesToClientRecordsArrays objectForKey:categoryName];
	if (categoryClientRecords == nil) {
	    categoryClientRecords = [NSMutableArray array];
	    [categoryNamesToClientRecordsArrays setObject:categoryClientRecords forKey:categoryName];
	}
	[categoryClientRecords insertObject:record inArraySortedUsingSelector:@selector(compareOrdering:)];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_defaultsDidChange:) name:NSUserDefaultsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_modifierFlagsChanged:) name:OAFlagsChangedNotification object:nil];
    return self;
}

// Properties

- (void)setHiddenPreferenceIdentifiers:(NSSet *)hiddenPreferenceIdentifiers;
{
    if (OFISEQUAL(_hiddenPreferenceIdentifiers, hiddenPreferenceIdentifiers))
        return;
    
    _hiddenPreferenceIdentifiers = hiddenPreferenceIdentifiers;
    [self _resetInterface];
}

// API

- (void)close;
{
    if ([_window isVisible])
        [_window performClose:nil];
}

- (NSWindow *)window;  // in case you want to do something nefarious to it like change its level, as OmniGraffle does
{
    [self _loadInterface];
    return _window;
}

- (void)setWindow:(NSWindow *)window;
{
    if (window != _window) {
        _window = OB_CHECKED_CAST(OAPreferencesWindow, window);
    }
}

- (NSWindow *)windowIfLoaded; // doesn't load the window
{
    return _window;
}

- (void)setTitle:(NSString *)title;
{
    [_window setTitle:title];
}

// Setting the current preference client

- (void)setCurrentClientByClassName:(NSString *)name;
{
    [self setCurrentClientByClassName:name completion:nil];
}

- (void)setCurrentClientRecord:(OAPreferenceClientRecord *)clientRecord;
{
    [self setCurrentClientRecord:clientRecord completion:nil];
}

- (void)setCurrentClientByClassName:(NSString *)name completion:(OAPreferenceClientChangeCompletion)completion;
{
    for (OAPreferenceClientRecord *clientRecord in _clientRecords) {
        if ([[clientRecord className] isEqualToString:name]) {
            [self setCurrentClientRecord:clientRecord completion:completion];
            return;
        }
    }
}

- (void)setCurrentClientRecord:(OAPreferenceClientRecord *)clientRecord completion:(OAPreferenceClientChangeCompletion)completion;
{    
    if (nonretained_currentClientRecord == clientRecord) {
        if (completion != nil) {
            completion(nonretained_currentClient);
        }
        return;
    }
    
    // Save changes in any editing text fields
    [_window setInitialFirstResponder:nil];
    [_window makeFirstResponder:nil];
    
    // Only do this when we are on screen to avoid sending become/resign twice.  If we are off screen, the client got resigned when it went off and the new one will get a become when it goes on screen.
    if ([_window isVisible])
        [nonretained_currentClient resignCurrentPreferenceClient];
    
    nonretained_currentClientRecord = clientRecord;
    nonretained_currentClient = [self _clientForRecord:clientRecord];
    
    [self _resetWindowTitle];
    
    // Remove old client box
    NSView *contentView = [self.preferenceBox contentView];
    NSView *oldView = [[contentView subviews] lastObject];
    [oldView removeFromSuperview];
    
    // Only do this when we are on screen to avoid sending become/resign twice.  If we are off screen, the client got resigned when it went off and the new one will get a become when it goes on screen.

    // As above, don't do this unless we are onscreen to avoid double become/resigns.
    if ([_window isVisible])
        [nonretained_currentClient willBecomeCurrentPreferenceClient];

    // Resize window for the new client box, after letting the client know that it's about to become current
    NSView *controlBox = [nonretained_currentClient controlBox];
    
    // It's an error for controlBox to be nil, but it's pretty unfriendly to resize our window to be infinitely high when that happens.
    NSSize controlBoxSize = (controlBox != nil ? [self _autosizeControlBox] : NSZeroSize);
    
    // Resize the window
    // We don't just tell the window to resize, because that tends to move the upper left corner (which will confuse the user)
    NSRect windowFrame = [NSWindow contentRectForFrameRect:[_window frame] styleMask:[_window styleMask]];
    CGFloat newWindowHeight = controlBoxSize.height + NSHeight([_globalControlsView frame]);
    if ([toolbar isVisible])
        newWindowHeight += NSHeight([[toolbar _toolbarView] frame]); 
    
    NSRect newWindowFrame = [NSWindow frameRectForContentRect:NSMakeRect(NSMinX(windowFrame), NSMaxY(windowFrame) - newWindowHeight, MAX(idealWidth, controlBoxSize.width), newWindowHeight) styleMask:[_window styleMask]];
    BOOL animate = [_window isVisible];
    NSTimeInterval animationDuration = animate ? [_window animationResizeTime:newWindowFrame] : 0;
    [_window setFrame:newWindowFrame display:YES animate:animate];
    
    [_nonretained_helpButton setHidden:[clientRecord helpURL] == nil];

    // Do this before putting the view in the view hierarchy to avoid flashiness in the controls.
    if ([_window isVisible])
        [self validateRestoreDefaultsButton];

    [nonretained_currentClient updateUI];
    
    // set up the global controls view
    if (self.helpButton)
        [self.helpButton setEnabled:([nonretained_currentClientRecord helpURL] != nil)];
    NSRect controlsRect = _globalControlsView.frame;
    controlsRect.size.width = contentView.frame.size.width;
    [_globalControlsView setFrame:controlsRect];
    
    [contentView addSubview:_globalControlsView];
    
    // Add the new client box to the view hierarchy
    if (controlBox) {
        [controlBox setFrameOrigin:NSMakePoint((CGFloat)floor((NSWidth([contentView frame]) - controlBoxSize.width) / 2.0), NSHeight([_globalControlsView frame]))];
        [contentView addSubview:controlBox];
    } else {
        OBASSERT_NOT_REACHED("Preference client %@ has no controlBox set", nonretained_currentClient);
    }
    
    // Highlight the initial first responder, and also tell the window what it should be because I think there is some voodoo with nextKeyView not working unless the window has an initial first responder.
    [_window setInitialFirstResponder:[nonretained_currentClient initialFirstResponder]];
    NSView *initialKeyView = [nonretained_currentClient initialFirstResponder];
    if (initialKeyView != nil && ![initialKeyView canBecomeKeyView])
        initialKeyView = [initialKeyView nextValidKeyView];
    [_window makeFirstResponder:initialKeyView];
    
    // Hook up the pane's keyView loop to ours.  returnToOriginalValuesButton is always present, but the help button might get removed if there is no help URL for this pane.
    [[nonretained_currentClient lastKeyView] setNextKeyView:self.returnToOriginalValuesButton];
    if (self.helpButton) {
	OBASSERT([self.returnToOriginalValuesButton nextKeyView] == self.helpButton); // set in nib
	[self.helpButton setNextKeyView:[nonretained_currentClient initialFirstResponder]];
    }
    
    // As above, don't do this unless we are onscreen to avoid double become/resigns.
    if ([_window isVisible]) {
        [nonretained_currentClient didBecomeCurrentPreferenceClient];
    }
    
    if (completion != nil) {
        // Attempt to only call the completion block if the client is still current at the time of dispatch
        OAPreferenceClient *client = nonretained_currentClient;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(animationDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (client == nonretained_currentClient) {
                completion(client);
            }
        });
    }
}

- (void)reloadCurrentClient;
{
    OBPRECONDITION(nonretained_currentClientRecord != nil);
    if (nonretained_currentClientRecord == nil) {
        return;
    }

    OAPreferenceClientRecord *currentClientRecord = nonretained_currentClientRecord;
    nonretained_currentClientRecord = nil; // nil to avoid early out in setter
    [self setCurrentClientRecord:currentClientRecord];
}

- (NSArray *)clientRecords;
{
    return _clientRecords;
}

- (NSString *)defaultKeySuffix;
{
    return _defaultKeySuffix;
}

- (OAPreferenceClientRecord *)clientRecordWithShortTitle:(NSString *)shortTitle;
{
    return _ClientRecordWithValueForKey(_clientRecords, @"shortTitle", shortTitle);
}

- (OAPreferenceClientRecord *)clientRecordWithIdentifier:(NSString *)identifier;
{
    return _ClientRecordWithValueForKey(_clientRecords, @"identifier", identifier);
}

- (OAPreferenceClient *)clientWithShortTitle:(NSString *)shortTitle;
{
    return [self _clientForRecord:[self clientRecordWithShortTitle: shortTitle]];
}

- (OAPreferenceClient *)clientWithIdentifier:(NSString *)identifier;
{
    return [self _clientForRecord:[self clientRecordWithIdentifier: identifier]];
}

- (OAPreferenceClient *)currentClient;
{
    return nonretained_currentClient;
}

- (void)iconView:(OAPreferencesIconView *)iconView buttonHitAtIndex:(NSUInteger)index;
{
    [self setCurrentClientRecord:[[iconView preferenceClientRecords] objectAtIndex:index]];
}

- (void)validateRestoreDefaultsButton;
{
    [self.returnToOriginalValuesButton setEnabled:[nonretained_currentClient haveAnyDefaultsChanged]];
}

// Outlets

@synthesize preferenceBox = _nonretained_preferenceBox;
@synthesize globalControlsView = _globalControlsView;
@synthesize helpButton = _nonretained_helpButton;
@synthesize returnToOriginalValuesButton = _nonretained_returnToOriginalValuesButton;

// Actions

- (IBAction)showPreferencesPanel:(id)sender;
{
    OBPRECONDITION([_clientRecords count] > 0); // did you forget to register your clients?

    // We'll avoid sending -will/-didBecomeCurrentPreferenceClient when the current client already has become the current client and hasn't received a -resignCurrentPreferenceClient.  We'll still update the UI on the client since we used to do that before this fix was made and it might be useful in some cases where external changes can be made to preferences.
    BOOL wasVisible = [_window isVisible];

    if (!wasVisible) {
	[self _loadInterface];
	[self _resetWindowTitle];
	
	// Let the current client know that it is about to be displayed.
	[nonretained_currentClient willBecomeCurrentPreferenceClient];
    }
    
    [self validateRestoreDefaultsButton];
    [nonretained_currentClient updateUI];
    [_window makeKeyAndOrderFront:sender];
    
    if (!wasVisible) {
	[nonretained_currentClient didBecomeCurrentPreferenceClient];
    }
}

- (IBAction)restoreDefaults:(id)sender;
{
    if (([[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSAlternateKeyMask) && ([[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSShiftKeyMask)) {
        // warn & wipe the entire defaults domain
        NSBundle *bundle = [OAPreferenceClient bundle];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedStringFromTableInBundle(@"Reset all preferences and other settings to their original values?", @"OmniAppKit", bundle, "message text for reset-to-defaults alert");
        alert.informativeText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Choosing Reset will restore all settings (including options not in this Preferences window, such as window sizes and toolbars) to the state they were in when %@ was first installed.", @"OmniAppKit", bundle, "informative text for reset-to-defaults alert"), [[NSProcessInfo processInfo] processName]];
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Reset", @"OmniAppKit", bundle, "alert panel button")];
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", bundle, "alert panel button")];
        [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode) {
            if (returnCode != NSAlertFirstButtonReturn)
                return;
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [nonretained_currentClient valuesHaveChanged];
        }];
    } else if ([[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSAlternateKeyMask) {
        // warn & wipe all prefs shown in the panel
        NSBundle *bundle = [OAPreferenceClient bundle];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedStringFromTableInBundle(@"Reset all preferences to their original values?", @"OmniAppKit", bundle, "message text for reset-to-defaults alert");
        alert.informativeText = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Choosing Reset will restore all settings in all preference panes to the state they were in when %@ was first installed.", @"OmniAppKit", bundle, "informative text for reset-to-defaults alert"), [[NSProcessInfo processInfo] processName]];
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Reset", @"OmniAppKit", bundle, "alert panel button")];
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniAppKit", bundle, "alert panel button")];
        [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode) {
            if (returnCode != NSAlertFirstButtonReturn)
                return;
            
            for (OAPreferenceClientRecord *aClientRecord in [self clientRecords]) {
                NSArray *preferenceKeys = [[NSArray array] arrayByAddingObjectsFromArray:[[aClientRecord defaultsDictionary] allKeys]];
                preferenceKeys = [preferenceKeys arrayByAddingObjectsFromArray:[aClientRecord defaultsArray]];
                
                for (NSString *aKey in preferenceKeys)
                    [[OFPreference preferenceForKey:aKey] restoreDefaultValue];
            }
            [nonretained_currentClient valuesHaveChanged];
        }];
    } else {
        // OAPreferenceClient will handle warning & reverting
        [nonretained_currentClient restoreDefaults:sender];
    }
}

- (IBAction)showNextClient:(id)sender;
{
    NSArray *sortedClientRecords = [self _sortedClientRecords];
    
    NSUInteger currentIndex = [sortedClientRecords indexOfObject:nonretained_currentClientRecord];
    if (currentIndex != NSNotFound && currentIndex+1 < [sortedClientRecords count])
        [self setCurrentClientRecord:[sortedClientRecords objectAtIndex:currentIndex+1]];
    else
        [self setCurrentClientRecord:[sortedClientRecords objectAtIndex:0]];
}

- (IBAction)showPreviousClient:(id)sender;
{
    NSArray *sortedClientRecords = [self _sortedClientRecords];

    NSUInteger currentIndex = [sortedClientRecords indexOfObject:nonretained_currentClientRecord];
    if (currentIndex != NSNotFound && currentIndex > 0)
        [self setCurrentClientRecord:[sortedClientRecords objectAtIndex:currentIndex-1]];
    else
        [self setCurrentClientRecord:[sortedClientRecords lastObject]];
}

- (IBAction)setCurrentClientFromToolbarItem:(id)sender;
{
    [self setCurrentClientRecord:[self clientRecordWithIdentifier:[sender itemIdentifier]]];
}

- (IBAction)showHelpForClient:(id)sender;
{
    NSString *helpURL = [nonretained_currentClientRecord helpURL];
    
    if (helpURL)
        [[OAApplication sharedApplication] showHelpURL:helpURL];
}

// NSWindow delegate

- (void)windowWillClose:(NSNotification *)notification;
{
    [[notification object] makeFirstResponder:nil];
    [nonretained_currentClient resignCurrentPreferenceClient];

    // Save settings immediately when closing the window
    [[OFPreferenceWrapper sharedPreferenceWrapper] synchronize];
}

- (void)windowDidResignKey:(NSNotification *)notification;
{
    [[notification object] makeFirstResponder:nil];
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client;
{
    if ([nonretained_currentClient respondsToSelector:_cmd])
        return [nonretained_currentClient performSelector:@selector(windowWillReturnFieldEditor:toObject:) withObject:sender withObject:client];
    return nil;
}

// NSToolbar delegate (We use an NSToolbar in OAPreferencesViewCustomizable)

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag;
{
    NSToolbarItem *newItem;

    newItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    [newItem setTarget:self];
    if ([itemIdentifier isEqualToString:@"OAPreferencesShowAll"]) {
        [newItem setAction:@selector(_showAllIcons:)];
        [newItem setLabel:NSLocalizedStringFromTableInBundle(@"Show All", @"OmniAppKit", [OAPreferenceController bundle], "preferences panel button")];
        [newItem setImage:[NSImage imageNamed:@"NSApplicationIcon"]];
    } else if ([itemIdentifier isEqualToString:@"OAPreferencesNext"]) {
        [newItem setAction:@selector(showNextClient:)];
        [newItem setLabel:NSLocalizedStringFromTableInBundle(@"Next", @"OmniAppKit", [OAPreferenceController bundle], "preferences panel button")];
        [newItem setImage:[NSImage imageNamed:NSImageNameGoRightTemplate]];
        [newItem setEnabled:NO]; // the first time these get added, we'll be coming up in "show all" mode, so they'll immediately diable anyway...
    } else if ([itemIdentifier isEqualToString:@"OAPreferencesPrevious"]) {
        [newItem setAction:@selector(showPreviousClient:)];
        [newItem setLabel:NSLocalizedStringFromTableInBundle(@"Previous", @"OmniAppKit", [OAPreferenceController bundle], "preferences panel button")];
        [newItem setImage:[NSImage imageNamed:NSImageNameGoLeftTemplate]];
        [newItem setEnabled:NO]; // ... so we disable them now to prevent visible flickering.
    } else { // it's for a preference client
        if ([self clientRecordWithIdentifier:itemIdentifier] == nil)
            return nil;
        
        [newItem setAction:@selector(setCurrentClientFromToolbarItem:)];
        [newItem setLabel:[[self clientRecordWithIdentifier:itemIdentifier] shortTitle]];
        [newItem setImage:[[self clientRecordWithIdentifier:itemIdentifier] iconImage]];
    }
    return newItem;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
{
    return defaultToolbarItems;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
{
    return allowedToolbarItems;
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar;
{
    return allowedToolbarItems;
}

#pragma mark -
#pragma mark NSToolbar validation

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem;
{
    NSString *itemIdentifier = [theItem itemIdentifier];
    if ([itemIdentifier isEqualToString:@"OAPreferencesPrevious"] || [itemIdentifier isEqualToString:@"OAPreferencesNext"])
        return (nonretained_currentClientRecord != nil);
    
    return YES;
}

#pragma mark -
#pragma mark NSMenuItemValidation

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    SEL action = [item action];
    if (action == @selector(runToolbarCustomizationPalette:))
        return NO;
        
    return YES;
}

#pragma mark -
#pragma mark Private

- (void)_loadInterface;
{
    if (_window != nil)
        return;    

    NSArray *objects;
    if (![[OAPreferenceController bundle] loadNibNamed:@"OAPreferences" owner:self topLevelObjects:&objects]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Failed to load OAPreferences nib" userInfo:nil];
    }

    _topLevelObjects = objects;

    // These don't seem to get set by the nib.  We want autosizing on so that clients can resize the window by a delta (though it'd be nicer for us to have API for that).
    [self.preferenceBox setAutoresizesSubviews:YES];
    [(NSView *)[self.preferenceBox contentView] setAutoresizingMask:[self.preferenceBox autoresizingMask]];
    [[self.preferenceBox contentView] setAutoresizesSubviews:YES];
    
    idealWidth = NSWidth([_globalControlsView frame]);
    [_window center];
    [_window setFrameAutosaveName:windowFrameSaveName];
    [_window setFrameUsingName:windowFrameSaveName force:YES];
    [self _resetInterface];
}

- (void)_resetInterface;
{
    NSArray *visibleClientRecordIdentifiers = [self _visibleClientRecordIdentifiers];
    if (visibleClientRecordIdentifiers.count == 1) {
        viewStyle = OAPreferencesViewSingle;
        [toolbar setVisible:NO];
    } else if (visibleClientRecordIdentifiers.count > 10 || [[self _categoryNames] count] > 1) {
        viewStyle = OAPreferencesViewCustomizable;
    } else {
        viewStyle = OAPreferencesViewMultiple;
    }

    // The previous call to -setCurrentClientRecord: won't have set up the UI since the UI wasn't loaded.  Also, since the UI wasn't loaded before, the client won't have received a -becomeCurrentPreferenceClient, so we don't need to worry about calling -resignCurrentPreferenceClient before setting this to nil to avoid a duplicate -becomeCurrentPreferenceClient.
    NSString *initialClientRecordIdentifier = nonretained_currentClientRecord.identifier;
    nonretained_currentClientRecord = nil;
    if ([_hiddenPreferenceIdentifiers containsObject:initialClientRecordIdentifier])
        initialClientRecordIdentifier = nil;

    switch (viewStyle) {
        case OAPreferencesViewSingle:
            initialClientRecordIdentifier = visibleClientRecordIdentifiers[0];
            break;
        case OAPreferencesViewCustomizable:
            [self _createShowAllItemsView];
            [self _setupShowAllToolbar];
            [self _showAllIcons:nil];
            break;
	default:
        case OAPreferencesViewMultiple:
            [self _setupMultipleToolbar];
	    if (initialClientRecordIdentifier == nil)
                initialClientRecordIdentifier = visibleClientRecordIdentifiers[0];
            break;
    }

    [self setCurrentClientRecord:[self clientRecordWithIdentifier:initialClientRecordIdentifier]];
}

- (void)_createShowAllItemsView;
{
    const unsigned int verticalSpaceBelowTextField = 4, verticalSpaceAboveTextField = 7, sideMargin = 12;
    CGFloat boxHeight = 12.0f;

    showAllIconsView = [[NSView alloc] initWithFrame:NSZeroRect];

    // This is lame.  We should really think up some way to specify the ordering of preferences in the plists.  But this is difficult since preferences can come from many places.
    NSArray *categoryNames = [self _categoryNames];
    NSUInteger categoryIndex = [categoryNames count];
    while (categoryIndex--) {
        NSString *categoryName = [categoryNames objectAtIndex:categoryIndex];
        NSArray *categoryClientRecords = [categoryNamesToClientRecordsArrays objectForKey:categoryName];

        // category preferences view
        OAPreferencesIconView *preferencesIconView = [[OAPreferencesIconView alloc] initWithFrame:[self.preferenceBox bounds]];
        [preferencesIconView setPreferenceController:self];
        [preferencesIconView setPreferenceClientRecords:categoryClientRecords];

        [showAllIconsView addSubview:preferencesIconView];
        [preferencesIconView setFrameOrigin:NSMakePoint(0, boxHeight)];
        [preferencesIconViews addObject:preferencesIconView];

        boxHeight += NSHeight([preferencesIconView frame]);

        // category header
        NSTextField *categoryHeaderTextField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        [categoryHeaderTextField setDrawsBackground:NO];
        [categoryHeaderTextField setBordered:NO];
        [categoryHeaderTextField setEditable:NO];
        [categoryHeaderTextField setSelectable:NO];
        [categoryHeaderTextField setTextColor:[NSColor controlTextColor]];
        [categoryHeaderTextField setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
        [categoryHeaderTextField setAlignment:NSLeftTextAlignment];
        [categoryHeaderTextField setStringValue:[[self class] _localizedCategoryNameForCategoryName:categoryName]];
        [categoryHeaderTextField sizeToFit];
        [showAllIconsView addSubview:categoryHeaderTextField];
        [categoryHeaderTextField setFrame:NSMakeRect(sideMargin, boxHeight + verticalSpaceBelowTextField, NSWidth([self.preferenceBox bounds]) - sideMargin, NSHeight([categoryHeaderTextField frame]))];

        boxHeight += NSHeight([categoryHeaderTextField frame]) + verticalSpaceAboveTextField;

        if (categoryIndex != 0) {
            const unsigned int separatorMargin = 15;
            NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(separatorMargin, boxHeight + verticalSpaceBelowTextField, NSWidth([self.preferenceBox bounds]) - separatorMargin - separatorMargin, 1)];
            [separator setBoxType:NSBoxSeparator];
            [showAllIconsView addSubview:separator];
            
            boxHeight += verticalSpaceAboveTextField + verticalSpaceBelowTextField;
        }
        boxHeight += verticalSpaceBelowTextField + 1;
    }

    [showAllIconsView setFrameSize:NSMakeSize(NSWidth([self.preferenceBox bounds]), boxHeight)];
}

- (NSArray <NSString *> *)_visibleClientRecordIdentifiers;
{
    return [[_clientRecords sortedArrayUsingSelector:@selector(compareOrdering:)] arrayByPerformingBlock:^id(OAPreferenceClientRecord *record) {
        NSString *identifier = record.identifier;
        if ([_hiddenPreferenceIdentifiers containsObject:identifier])
            return nil;
        else
            return identifier;
    }];
}

- (void)_setupMultipleToolbar;
{
    allowedToolbarItems = [self _visibleClientRecordIdentifiers];
    defaultToolbarItems = allowedToolbarItems;
    
    toolbar = [[OAPreferencesToolbar alloc] initWithIdentifier:@"OAPreferences"];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO]; // Don't store the configured items or new items won't show up!
    [toolbar setDelegate:self];
    [_window setToolbar:toolbar];
}

- (void)_setupShowAllToolbar;
{
    NSArray *constantToolbarItems = @[
        @"OAPreferencesShowAll",
        @"OAPreferencesPrevious",
        @"OAPreferencesNext",
        // NSToolbarFlexibleSpaceItemIdentifier,
        // @"OAPreferencesSearch",
    ];

    NSArray *defaultClients = [[NSUserDefaults standardUserDefaults] arrayForKey:@"FavoritePreferenceIdentifiers"];
    NSArray *allClients = [self _visibleClientRecordIdentifiers];
    defaultToolbarItems = [constantToolbarItems arrayByAddingObjectsFromArray:defaultClients];
    allowedToolbarItems = [constantToolbarItems arrayByAddingObjectsFromArray:allClients];

    toolbar = [[OAPreferencesToolbar alloc] initWithIdentifier:@"OAPreferenceIdentifiers"];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO];
    [toolbar setDelegate:self];
    [_window setToolbar:toolbar];
}

- (void)_resetWindowTitle;
{
    NSString *name = nil;
    
    if (viewStyle != OAPreferencesViewSingle) {
        name = [nonretained_currentClientRecord title];
        if ([toolbar respondsToSelector:@selector(setSelectedItemIdentifier:)]) {
            if (nonretained_currentClientRecord != nil)
                [toolbar setSelectedItemIdentifier:[nonretained_currentClientRecord identifier]];
            else
                [toolbar setSelectedItemIdentifier:@"OAPreferencesShowAll"];
        }
    }
    if (name == nil || [name isEqualToString:@""])
        name = [[NSProcessInfo processInfo] processName];
    [_window setTitle:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ Preferences", @"OmniAppKit", [OAPreferenceController bundle], "preferences panel title format"), name]];
}

- (OAPreferenceClient *)_clientForRecord:(OAPreferenceClientRecord *)record;
{
    OBPRECONDITION(record != nil);
    if (record == nil)
	return nil;
    
    NSString *identifier = [record identifier];
    OAPreferenceClient *client = [_clientByRecordIdentifier objectForKey:identifier];
    if (client == nil) {
	client = [record newClientInstanceInController:self];
	[_clientByRecordIdentifier setObject:client forKey:identifier];
    }
    return client;
}

- (void)_showAllIcons:(id)sender;
{
    // Are we already showing?
    if ([[[self.preferenceBox contentView] subviews] lastObject] == showAllIconsView)
        return;

    // Save changes in any editing text fields
    [_window setInitialFirstResponder:nil];
    [_window makeFirstResponder:nil];

    // Clear out current preference and reset window title
    nonretained_currentClientRecord = nil;
    nonretained_currentClient = nil;
    [[[self.preferenceBox contentView] subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self _resetWindowTitle];
        
    // Resize window
    NSRect windowFrame = [NSWindow contentRectForFrameRect:[_window frame] styleMask:[_window styleMask]];
    CGFloat newWindowHeight = NSHeight([showAllIconsView frame]);
    if ([toolbar isVisible])
        newWindowHeight += NSHeight([[toolbar _toolbarView] frame]);
    NSRect newWindowFrame = [NSWindow frameRectForContentRect:NSMakeRect(NSMinX(windowFrame), NSMaxY(windowFrame) - newWindowHeight, idealWidth, newWindowHeight) styleMask:[_window styleMask]];
    [_window setFrame:newWindowFrame display:YES animate:[_window isVisible]];

    // Add new icons view
    [self.preferenceBox addSubview:showAllIconsView];
}

static NSString * const IdealWidthConstraintIdentifier = @"OAPreferenceController.idealWidthConstraint";

- (NSSize)_autosizeControlBox
{
    NSView *controlBox = [nonretained_currentClient controlBox];
    
    if (!nonretained_currentClient.wantsAutosizing) {
#ifdef OMNI_ASSERTIONS_ON
        static NSMutableSet *IdentifiersOfClientsComplainedAbout = nil;
        if (IdentifiersOfClientsComplainedAbout == nil) {
            IdentifiersOfClientsComplainedAbout = [NSMutableSet new];
        }
        NSString *clientIdentifier = nonretained_currentClientRecord.identifier;
        if (![IdentifiersOfClientsComplainedAbout containsObject:clientIdentifier]) {
            [IdentifiersOfClientsComplainedAbout addObject:clientIdentifier];
            BOOL likelyUsingAutoLayout = NO;
            for (NSView *subview in controlBox.subviews) {
                if (subview.translatesAutoresizingMaskIntoConstraints == NO) {
                    likelyUsingAutoLayout = YES;
                    break;
                }
            }
            OBASSERT(!likelyUsingAutoLayout, @"OAPreferenceClient subclass %@ appears to use autolayout but does not override %@ to adopt autosizing of its controlBox. It probably should eventually. Maybe soon?", nonretained_currentClientRecord.className, NSStringFromSelector(@selector(wantsAutosizing)));
        }
#endif
        return controlBox.frame.size;
    }
    
    // N.B. See documentation of OAPreferenceClient's wantsAutosizing property.
    NSLayoutConstraint *idealWidthConstraint = nil;
    idealWidthConstraint = [controlBox.constraints first:^BOOL(NSLayoutConstraint *constraint) {
        return [constraint.identifier isEqualToString:IdealWidthConstraintIdentifier];
    }];
    if (idealWidthConstraint == nil) {
        idealWidthConstraint = [NSLayoutConstraint constraintWithItem:controlBox attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0f constant:idealWidth];
        idealWidthConstraint.identifier = IdealWidthConstraintIdentifier;
        idealWidthConstraint.priority = OAPreferenceClientControlBoxFixedWidthPriority;
        idealWidthConstraint.active = YES;
    } else {
        idealWidthConstraint.constant = idealWidth;
    }
    
    NSSize fittingSize = controlBox.fittingSize;
    NSRect frame = controlBox.frame;
    frame.size = fittingSize;
    controlBox.frame = frame;
    return fittingSize;
}

- (void)_defaultsDidChange:(NSNotification *)notification;
{
    if ([_window isVisible]) {
        // Do this later since this gets called inside a lock that we need
        [self queueSelector:@selector(validateRestoreDefaultsButton)];
    }
}

- (void)_modifierFlagsChanged:(NSNotification *)note;
{
    BOOL optionDown = ([[note object] modifierFlags] & NSAlternateKeyMask) ? YES : NO;
    NSButton *returnToOriginalValuesButton = self.returnToOriginalValuesButton;

    if (optionDown) {
        [returnToOriginalValuesButton setEnabled:YES];
        [returnToOriginalValuesButton setTitle:NSLocalizedStringFromTableInBundle(@"Reset All", @"OmniAppKit", [OAPreferenceController bundle], "reset-to-defaults button title")];
        [returnToOriginalValuesButton setToolTip:NSLocalizedStringFromTableInBundle(@"Return all settings to default values", @"OmniAppKit", [OAPreferenceController bundle], "reset-to-defaults button tooltip")];
    } else {
        [returnToOriginalValuesButton setEnabled:[nonretained_currentClient haveAnyDefaultsChanged]];
        [returnToOriginalValuesButton setTitle:NSLocalizedStringFromTableInBundle(@"Reset", @"OmniAppKit", [OAPreferenceController bundle], "reset-to-defaults button title")];
        [returnToOriginalValuesButton setToolTip:NSLocalizedStringFromTableInBundle(@"Return settings in this pane to default values", @"OmniAppKit", [OAPreferenceController bundle], "reset-to-defaults button tooltip")];
    }
}

//

- (NSArray *)_categoryNames;
{
    Class cls = [self class];
    return [[categoryNamesToClientRecordsArrays allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *name1, NSString *name2) {
        float priority1 = [cls _priorityForCategoryName:name1];
        float priority2 = [cls _priorityForCategoryName:name2];
        if (priority1 == priority2)
            return [[cls _localizedCategoryNameForCategoryName:name1] caseInsensitiveCompare:[cls _localizedCategoryNameForCategoryName:name2]];
        else if (priority1 > priority2)
            return NSOrderedAscending;
        else // priority1 < priority2
            return NSOrderedDescending;
    }];
}

- (NSArray *)_sortedClientRecords;
{
    NSMutableArray *sortedClientRecords = [NSMutableArray array];
    for (NSString *categoryName in [self _categoryNames])
        [sortedClientRecords addObjectsFromArray:[categoryNamesToClientRecordsArrays objectForKey:categoryName]];
    return sortedClientRecords;
}

+ (void)_registerCategoryName:(NSString *)categoryName localizedName:(NSString *)localizedCategoryName priorityNumber:(NSNumber *)priorityNumber;
{
    if (localizedCategoryName != nil && ![localizedCategoryName isEqualToString:categoryName])
        [LocalizedCategoryNames setObject:localizedCategoryName forKey:categoryName];
    if (priorityNumber != nil)
        [CategoryPriorities setObject:priorityNumber forKey:categoryName];
}

+ (NSString *)_localizedCategoryNameForCategoryName:(NSString *)categoryName;
{
    return [LocalizedCategoryNames objectForKey:categoryName defaultObject:categoryName];
}

+ (float)_priorityForCategoryName:(NSString *)categoryName;
{
    NSNumber *priority;

    priority = [CategoryPriorities objectForKey:categoryName];
    if (priority != nil)
        return [priority floatValue];
    else
        return 0.0f;
}

+ (void)_registerClassName:(NSString *)className inCategoryNamed:(NSString *)categoryName description:(NSDictionary *)description;
{
    OAPreferenceClientRecord *newRecord;
    NSDictionary *defaultsDictionary;
    NSString *titleEnglish, *title, *iconName, *nibName, *identifier, *shortTitleEnglish, *shortTitle;
    NSBundle *classBundle = [OFBundledClass bundleForClassNamed:className];

    defaultsDictionary = [description objectForKey:@"defaultsDictionary"];
    if (defaultsDictionary)
        [[NSUserDefaults standardUserDefaults] registerDefaults:defaultsDictionary];
    else
        defaultsDictionary = [NSDictionary dictionary]; // placeholder
    
    NSString *minimumOSVersionString = [description objectForKey:@"minimumOSVersion"];
    if (![NSString isEmptyString:minimumOSVersionString]) {
	OFVersionNumber *minimumOSVersion = [[OFVersionNumber alloc] initWithVersionString:minimumOSVersionString];
	OFVersionNumber *currentOSVersion = [OFVersionNumber userVisibleOperatingSystemVersionNumber];
	
	BOOL fulfillsMinimumRequirements = ([currentOSVersion compareToVersionNumber:minimumOSVersion] != NSOrderedAscending);
	if (!fulfillsMinimumRequirements)
	    return;
    }
    
    titleEnglish = [description objectForKey:@"title"];
    if (titleEnglish == nil)
        titleEnglish = [NSString stringWithFormat:@"Localized Title for Preference Class %@", className];
    title = [classBundle localizedStringForKey:titleEnglish value:@"" table:@"Preferences"];

    if (!(className && title))
        return;
    
    iconName = [description objectForKey:@"icon"];
    if (iconName == nil || [iconName isEqualToString:@""])
        iconName = className;
    nibName = [description objectForKey:@"nib"];
    if (nibName == nil || [nibName isEqualToString:@""])
        nibName = className;

    shortTitleEnglish = [description objectForKey:@"shortTitle"];
    if (shortTitleEnglish == nil) {
        shortTitleEnglish = [NSString stringWithFormat:@"Localized Short Title for Preference Class %@", className];
        shortTitle = [classBundle localizedStringForKey:shortTitleEnglish value:@"" table:@"Preferences"];
        if ([shortTitle isEqualToString:shortTitleEnglish])
            shortTitle = nil; // there's no localization for the short title specifically, so we'll let it client class default the short title to the localized version of the @"title" key's value
    } else
        shortTitle = [classBundle localizedStringForKey:shortTitleEnglish value:@"" table:@"Preferences"];
    
    identifier = [description objectForKey:@"identifier"];
    if (identifier == nil) {
        // Before we introduced a separate notion of identifiers, we simply used the short title (which defaulted to the title)
        identifier = [description objectForKey:@"shortTitle" defaultObject:titleEnglish];
    }

    // All our preference pane identifiers should really be in reverse DNS style now.
    OBASSERT([identifier containsString:@"."] || [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.omnigroup.OmniWeb6"]);
    
    // Allow client records to hidden by default.  This is useful for developer preferences or other preference panes that aren't fit for human consumption yet.
    if ([description boolForKey:@"hidden" defaultValue:NO]) {
        // If it defaults to hidden, check if there is a user default to make it specifically visible.
        if (![[NSUserDefaults standardUserDefaults] boolForKey:[identifier stringByAppendingString:@".visible"]])
            return;
    }
    
    // If we got back a non-localized titles, remove the suffix if needed so that it never appears in the UI; it's a localization implementation detail
    NSString *longTitleSuffix = @" [LONG]";
    if ([title hasSuffix:longTitleSuffix]) {
        title = [title substringToIndex:(title.length - longTitleSuffix.length)];
    }

    NSString *shortTitleSuffix = @" [SHORT]";
    if ([shortTitle hasSuffix:shortTitleSuffix]) {
        shortTitle = [shortTitle substringToIndex:(shortTitle.length - shortTitleSuffix.length)];
    }

    newRecord = [[OAPreferenceClientRecord alloc] initWithCategoryName:categoryName];
    [newRecord setIdentifier:identifier];
    [newRecord setClassName:className];
    [newRecord setTitle:title];
    [newRecord setShortTitle:shortTitle];
    [newRecord setIconName:iconName];
    [newRecord setNibName:nibName];
    [newRecord setHelpURL:[description objectForKey:@"helpURL"]];
    [newRecord setOrdering:[description objectForKey:@"ordering"]];
    [newRecord setDefaultsDictionary:defaultsDictionary];
    [newRecord setDefaultsArray:[description objectForKey:@"defaultsArray"]];

    [AllClientRecords addObject:newRecord];
}

@end

static NSAppleEventDescriptor *whose(OSType form, OSType want, NSAppleEventDescriptor *seld, NSAppleEventDescriptor *container)
{
    NSAppleEventDescriptor *obj = [NSAppleEventDescriptor recordDescriptor];
    
    if (!container)
        container = [NSAppleEventDescriptor nullDescriptor];
    
    [obj setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:form] forKeyword:keyAEKeyForm];
    [obj setDescriptor:[NSAppleEventDescriptor descriptorWithEnumCode:want] forKeyword:keyAEDesiredClass];
    [obj setDescriptor:seld forKeyword:keyAEKeyData];
    [obj setDescriptor:container forKeyword:keyAEContainer];
    
    return [obj coerceToDescriptorType:'obj '];
}

BOOL OAOpenSystemPreferencePane(NSString *paneIdentifier, NSString *tabIdentifier)
{
#ifdef OMNI_ASSERTIONS_ON
    /* You'll need this entitlement in order for this code to work from a sandboxed application:
     
       <key>com.apple.security.scripting-targets</key>
       <dict>
           <!-- Open System Preference panes -->
           <key>com.apple.systempreferences</key>
           <array>
               <string>preferencepane.reveal</string>
           </array>
       </dict>
    */

    if ([[NSProcessInfo processInfo] isSandboxed]) {
        NSDictionary *entitlements = [[NSProcessInfo processInfo] effectiveCodeSigningEntitlements:NULL];
        NSDictionary *scriptingTargets = entitlements[@"com.apple.security.scripting-targets"];
        NSArray *accessGroups = scriptingTargets[@"com.apple.systempreferences"];
        OBASSERT([accessGroups containsObject:@"preferencepane.reveal"], "Missing scripting target entitlement needed in order to open System Preference panes.");
    }
#endif

    NSString *systemPreferencesBundleID = @"com.apple.systempreferences";
    NSAppleEventDescriptor *target = whose(formUniqueID, 'xppb', [NSAppleEventDescriptor descriptorWithString:paneIdentifier], nil);
    if (tabIdentifier)
        target = whose(formName, 'xppa', [NSAppleEventDescriptor descriptorWithString:tabIdentifier], target);
    
    NSData *prefsBundleID = [systemPreferencesBundleID dataUsingEncoding:NSUTF8StringEncoding];

    OSErr err;
    OSStatus osst;
    AppleEvent reveal, reply;
    
    osst = AEBuildAppleEvent('misc','mvis',
                      typeApplicationBundleID, [prefsBundleID bytes], [prefsBundleID length],
                      kAutoGenerateReturnID,
                      kAnyTransactionID,
                      &reveal, NULL, "'----':@", [target aeDesc]);
    if (osst !=  aeBuildSyntaxNoErr)
        return NO;
    
    // Send the event with a timeout of 5 seconds. That should be long enough to get a failure response, but not so long that it'll be really annoying if there's a holdup for some reason.
    UInt32 aevtTimeout = 5 * 60;
    
    err = AESend(&reveal, &reply, kAEWaitReply|kAEAlwaysInteract|kAECanSwitchLayer, kAENormalPriority, aevtTimeout, NULL, NULL);
    if (err == procNotFound) {
        // Prefs hasn't been launched, perhaps.
        BOOL ok;
        ok = [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:systemPreferencesBundleID
                                                                  options:NSWorkspaceLaunchWithoutActivation
                                           additionalEventParamDescriptor:nil
                                                         launchIdentifier:NULL];
        if (ok)
            err = AESend(&reveal, &reply, kAEWaitReply|kAEAlwaysInteract|kAECanSwitchLayer, kAENormalPriority, aevtTimeout, NULL, NULL);
    }
    AEDisposeDesc(&reveal);
    if (err != noErr)
        return NO;
    
    BOOL successResponse = YES;
    AEDesc dummy;
    
    err = AEGetParamDesc(&reply, keyErrorNumber, typeWildCard, &dummy);
    if (err == noErr) {
        AEDisposeDesc(&dummy);
        successResponse = NO;
    } else {
        err = AEGetParamDesc(&reply, keyErrorString, typeWildCard, &dummy);
        if (err == noErr) {
            AEDisposeDesc(&dummy);
            successResponse = NO;
        }
    }
    AEDisposeDesc(&reply);
    
    // Finally, bring System Preferences to the foreground
    NSRunningApplication *application = [[NSRunningApplication runningApplicationsWithBundleIdentifier:systemPreferencesBundleID] lastObject];
    [application activateWithOptions:0];

    return successResponse;
}
