/*
    ManDrake - Native open-source Mac OS X man page editor
    Copyright (c) 2004-2016, Sveinbjorn Thordarson <sveinbjornt@gmail.com>

    Redistribution and use in source and binary forms, with or without modification,
    are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, this
    list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright notice, this
    list of conditions and the following disclaimer in the documentation and/or other
    materials provided with the distribution.

    3. Neither the name of the copyright holder nor the names of its contributors may
    be used to endorse or promote products derived from this software without specific
    prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
    IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
    INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
    NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
    WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

#import <WebKit/WebKit.h>
#import <stdlib.h>
#import "Common.h"
#import "ManDrakeDocument.h"
#import "CustomACEView.h"
#import "NSWorkspace+Additions.h"
#import "ACEView/ACEThemeNames.h"
#import "ACEView/ACEModes.h"
#import "ManDrakeApplicationDelegate.h"

@interface ManDrakeDocument()
{
    IBOutlet WebView *webView;
    IBOutlet NSPopUpButton *refreshTypePopupButton;
    IBOutlet NSProgressIndicator *refreshProgressIndicator;
    IBOutlet CustomACEView *aceView;
    IBOutlet NSTextField *statusTextField;
    IBOutlet NSTextField *warningsTextField;
    IBOutlet NSPopUpButton *themePopupButton;
    IBOutlet NSButton *editorActionButton;
    IBOutlet NSButton *previewActionButton;
    
    NSPoint currentScrollPosition;
    NSTimer *refreshTimer;
    NSString *fileString;
    
    dispatch_queue_t backgroundQueue;
}

- (IBAction)refresh:(id)sender;

- (IBAction)makeTextLarger:(id)sender;
- (IBAction)makeTextSmaller:(id)sender;
- (IBAction)makePreviewTextLarger:(id)sender;
- (IBAction)makePreviewTextSmaller:(id)sender;

- (IBAction)editorActionButtonPressed:(id)sender;
- (IBAction)previewActionButtonPressed:(id)sender;

- (IBAction)loadManMdocTemplate:(id)sender;
- (IBAction)loadDefaultManTemplate:(id)sender;

@end

@implementation ManDrakeDocument

#pragma mark -

- (void)dealloc {
    [self stopObservingDefaults];
}

#pragma mark - NSDocument

- (NSString *)windowNibName
{
    return @"ManDrakeDocument";
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    BOOL readSuccess = NO;
    NSString *fileContents = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!fileContents && outError) {
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileReadUnknownError userInfo:nil];
    }
    if (fileContents) {
        readSuccess = YES;
        fileString = fileContents;
    }
    return readSuccess;
}

- (BOOL)writeToURL:(NSURL *)url
            ofType:(NSString *)typeName
  forSaveOperation:(NSSaveOperationType)saveOperation
originalContentsURL:(NSURL *)originalContentsURL
             error:(NSError **)outError {
    return [[aceView string] writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:outError];
}

- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings error:(NSError * _Nullable *)outError {
    NSPrintInfo *printInfo = [self printInfo];
    NSPrintOperation *printOp = [NSPrintOperation printOperationWithView:webView printInfo:printInfo];
    return printOp;
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController {
    [super windowControllerDidLoadNib:aController];

    backgroundQueue = dispatch_queue_create("org.sveinbjorn.ManDrake.backgroundQueue", DISPATCH_QUEUE_SERIAL);
    
    [self startObservingDefaults];
    
    ACETheme theme = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorTheme] intValue];
    [aceView setTheme:theme];
    
    [themePopupButton removeAllItems];
    [themePopupButton addItemsWithTitles:[ACEThemeNames humanThemeNames]];
    [themePopupButton selectItemAtIndex:theme];
    
    [aceView setDelegate:self];
    if ([[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorSyntaxHighlighting] boolValue]) {
        [aceView setModeByNameString:@"groff"];
    }
    if ([[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorShowInvisibles] boolValue]) {
        [aceView setShowInvisibles:YES];
    }
    
    [aceView setFontSize:[[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorFontSize] intValue]];
    
    if (fileString) {
        @autoreleasepool {
            [aceView setString:fileString];
            fileString = nil;
        }
    } else {
        [self loadDefaultManTemplate:self];
    }
    
    BOOL softWrap = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorSoftLineWrap] boolValue];
    [aceView setUseSoftWrap:softWrap];
   
    [self setWebViewFontSize:[[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsPreviewFontSize] intValue]];
    
    id appDelegate = (ManDrakeApplicationDelegate *)[[NSApplication sharedApplication] delegate];
    [editorActionButton setMenu:[appDelegate editorMenu]];
    [previewActionButton setMenu:[appDelegate previewMenu]];
}

#pragma mark - Defaults observation

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if ([keyPath hasSuffix:kDefaultsEditorTheme]) {
        ACETheme theme = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorTheme] intValue];
        [aceView setTheme:theme];
    }
    else if ([keyPath hasSuffix:kDefaultsEditorShowInvisibles]) {
        BOOL showInvisibles = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorShowInvisibles] intValue];
        [aceView setShowInvisibles:showInvisibles];
    }
    else if ([keyPath hasSuffix:kDefaultsEditorSyntaxHighlighting]) {
        BOOL highlightSyntax = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorSyntaxHighlighting] intValue];
        if (highlightSyntax) {
            [aceView setModeByNameString:@"groff"];
        } else {
            [aceView setMode:ACEModeASCIIDoc];
        }
    }
    else if ([keyPath hasSuffix:kDefaultsEditorSoftLineWrap]) {
        BOOL softWrap = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorSoftLineWrap] intValue];
        [aceView setUseSoftWrap:softWrap];
    }
    else if ([keyPath hasSuffix:kDefaultsEditorFontSize]) {
        int fontSize = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsEditorFontSize] intValue];
        [aceView setFontSize:fontSize];
    }
    else if ([keyPath hasSuffix:kDefaultsPreviewInvert]) {
        [self refresh:self];
    }
}

- (void)startObservingDefaults {
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                              forKeyPath:VALUES_KEYPATH(kDefaultsEditorTheme)
                                                                 options:NSKeyValueObservingOptionNew
                                                                 context:NULL];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                              forKeyPath:VALUES_KEYPATH(kDefaultsEditorFontSize)
                                                                 options:NSKeyValueObservingOptionNew
                                                                 context:NULL];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                              forKeyPath:VALUES_KEYPATH(kDefaultsEditorShowInvisibles)
                                                                 options:NSKeyValueObservingOptionNew
                                                                 context:NULL];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                              forKeyPath:VALUES_KEYPATH(kDefaultsEditorSyntaxHighlighting)
                                                                 options:NSKeyValueObservingOptionNew
                                                                 context:NULL];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                              forKeyPath:VALUES_KEYPATH(kDefaultsEditorSoftLineWrap)
                                                                 options:NSKeyValueObservingOptionNew
                                                                 context:NULL];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                              forKeyPath:VALUES_KEYPATH(kDefaultsPreviewRefreshStyle)
                                                                 options:NSKeyValueObservingOptionNew
                                                                 context:NULL];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                              forKeyPath:VALUES_KEYPATH(kDefaultsPreviewInvert)
                                                                 options:NSKeyValueObservingOptionNew
                                                                 context:NULL];
}

- (void)stopObservingDefaults {
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
                                                                 forKeyPath:VALUES_KEYPATH(kDefaultsEditorTheme)];
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
                                                                 forKeyPath:VALUES_KEYPATH(kDefaultsEditorFontSize)];
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
                                                                 forKeyPath:VALUES_KEYPATH(kDefaultsEditorShowInvisibles)];
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
                                                                 forKeyPath:VALUES_KEYPATH(kDefaultsEditorSyntaxHighlighting)];
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
                                                                 forKeyPath:VALUES_KEYPATH(kDefaultsEditorSoftLineWrap)];
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
                                                                 forKeyPath:VALUES_KEYPATH(kDefaultsPreviewRefreshStyle)];
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self
                                                                 forKeyPath:VALUES_KEYPATH(kDefaultsPreviewInvert)];
}

#pragma mark - Editor

- (IBAction)editorActionButtonPressed:(id)sender {
    NSRect screenRect = [self.windowControllers[0].window convertRectToScreen:[(NSButton *)sender frame]];
    NSMenu *menu = [(ManDrakeApplicationDelegate *)[[NSApplication sharedApplication] delegate] editorMenu];
    [menu popUpMenuPositioningItem:nil atLocation:screenRect.origin inView:nil];
}

- (IBAction)themeChanged:(id)sender {
    [aceView setTheme:[themePopupButton indexOfSelectedItem]];
}

- (void)changeFontSize:(CGFloat)delta {
//    NSLog([aceView fontSize]);
    //    [[NSUserDefaults standardUserDefaults] setObject:@([aceView fontSize])
//                                              forKey:@"EditorFontSize"];
}

- (IBAction)makeTextLarger:(id)sender {
    [self changeFontSize:1];
}

- (IBAction)makeTextSmaller:(id)sender {
    [self changeFontSize:-1];
}

- (void)setWebViewFontSize:(int)delta {
    while (delta != 0) {
        if (delta < 0) {
            [self changePreviewFontSize:-1];
            delta++;
        } else {
            [self changePreviewFontSize:1];
            delta--;
        }
    }
}

- (void)changePreviewFontSize:(CGFloat)delta {
    (delta > 0) ? [webView makeTextLarger:self] : [webView makeTextSmaller:self];
}

- (IBAction)makePreviewTextLarger:(id)sender {
    int currentSizeDelta = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsPreviewFontSize] intValue];
    currentSizeDelta += 1;
    [[NSUserDefaults standardUserDefaults] setObject:@(currentSizeDelta) forKey:kDefaultsPreviewFontSize];
    [self changePreviewFontSize:1];
}

- (IBAction)makePreviewTextSmaller:(id)sender {
    int currentSizeDelta = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsPreviewFontSize] intValue];
    currentSizeDelta -= 1;
    [[NSUserDefaults standardUserDefaults] setObject:@(currentSizeDelta) forKey:kDefaultsPreviewFontSize];
    [self changePreviewFontSize:-1];
}

#pragma mark - Web Preview

- (IBAction)refresh:(id)sender {
	// generate preview
	[refreshProgressIndicator startAnimation:self];
	[self refreshWebView];
	[refreshProgressIndicator stopAnimation:self];
}

- (void)textDidChange:(NSNotification *)aNotification {
    NSString *refreshText = [refreshTypePopupButton titleOfSelectedItem];

    if ([refreshText isEqualToString:@"Manually"]) {
        return;
    }
    
	// use delayed timer
    if (refreshTimer != nil)
    {
        [refreshTimer invalidate];
        refreshTimer = nil;
    }
    NSTimeInterval delay = [refreshText isEqualToString:@"Live"] ? 0.01 : 0.2;
    refreshTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                    target:self
                                                  selector:@selector(updatePreview)
                                                  userInfo:nil
                                                   repeats:NO];
}

- (void)refreshWebView {
    NSString *manText = [aceView string];
    if (manText == nil || [manText length] == 0) {
        [[webView mainFrame] loadHTMLString:@"" baseURL:nil];
        return;
    }
    
    dispatch_async(backgroundQueue, ^{
        
        // Create nroff task
        NSTask *nroffTask = [[NSTask alloc] init];
        [nroffTask setLaunchPath:@"/usr/bin/nroff"];
        [nroffTask setArguments:@[@"-mandoc"]];
        
        NSPipe *nroffOutputPipe = [NSPipe pipe];
        NSPipe *nroffInputPipe = [NSPipe pipe];
        [nroffTask setStandardOutput:nroffOutputPipe];
        [nroffTask setStandardInput:nroffInputPipe];
        
        NSFileHandle *nroffWriteHandle = [nroffInputPipe fileHandleForWriting];
        
        // Create cat2html task
        NSTask *catTask = [[NSTask alloc] init];
        [catTask setLaunchPath:[[NSBundle mainBundle] pathForResource:@"cat2html" ofType:nil]];
        [catTask setArguments:@[]];
        
        NSPipe *catOutputPipe = [NSPipe pipe];
        [catTask setStandardOutput:catOutputPipe];
        [catTask setStandardInput:nroffOutputPipe];
        
        NSFileHandle *catReadHandle = [catOutputPipe fileHandleForReading];
        
        [nroffTask launch];
        [catTask launch];
        
        // Write string to nroff's stdin
        [nroffWriteHandle writeData:[manText dataUsingEncoding:NSUTF8StringEncoding]];
        [nroffWriteHandle closeFile];
        
        [nroffTask waitUntilExit];
        [catTask waitUntilExit];
        
        // Read output from cat2html's stdout
        NSMutableString *htmlString = [[NSMutableString alloc] initWithData:[catReadHandle readDataToEndOfFile]
                                                                   encoding:NSUTF8StringEncoding];
        
        dispatch_async(dispatch_get_main_queue(), ^{
        
            if ([htmlString length] == 0 || htmlString == nil) {
                [[webView mainFrame] loadHTMLString:@"<strong>Nil output from cat2html</strong>" baseURL:nil];
                NSLog(@"Nil output from cat2html");
                return;
            }
            
            // get the current scroll position of the document view of the web view
            NSScrollView *theScrollView = [[[[webView mainFrame] frameView] documentView] enclosingScrollView];
            NSRect scrollViewBounds = [[theScrollView contentView] bounds];
            currentScrollPosition = scrollViewBounds.origin;
            
            // invert black/white
            BOOL invert = [[[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsPreviewInvert] boolValue];
            if (invert) {
                NSString *bgColor = invert ? @"black" : @"white";
                NSString *fgColor = invert ? @"white" : @"black";
                NSString *bodyTag = [NSString stringWithFormat:@"<body bgcolor=\"%@\" text=\"%@\">", bgColor, fgColor];
                [htmlString replaceOccurrencesOfString:@"<body>"
                                            withString:bodyTag
                                               options:NSCaseInsensitiveSearch
                                                 range:NSMakeRange(0, 50)];
            }
            
            [[webView mainFrame] loadHTMLString:htmlString baseURL:nil];
        });
    });
}

// delegate method we receive when done loading the html file.
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
	// restore the scroll position
	[[[[webView mainFrame] frameView] documentView] scrollPoint:currentScrollPosition];
}

- (void)updatePreview {
	[self refresh:self];
	[refreshTimer invalidate];
	refreshTimer = nil;
}

#pragma mark - Check syntax

- (IBAction)previewActionButtonPressed:(id)sender {
    NSRect screenRect = [self.windowControllers[0].window convertRectToScreen:[(NSButton *)sender frame]];
    NSMenu *menu = [(ManDrakeApplicationDelegate *)[[NSApplication sharedApplication] delegate] previewMenu];
    [menu popUpMenuPositioningItem:nil atLocation:screenRect.origin inView:[sender superview]];
    
    NSLog(@"%@", NSStringFromRect([sender frame]));
}

- (IBAction)checkSyntaxButtonPressed:(id)sender {
    [self updateAnnotations];
}

- (void)updateAnnotations {
    dispatch_async(backgroundQueue, ^{
    
        NSArray *warningAnnotations = [self checkSyntax];
    
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [aceView setAnnotations:warningAnnotations];
            if ([warningAnnotations count]) {
                [warningsTextField setStringValue:[NSString stringWithFormat:@"%lu warnings", (unsigned long)[warningAnnotations count]]];
            }
            [warningsTextField setTag:[warningAnnotations count]];
        });
    });
}

- (NSArray *)checkSyntax {
    NSString *manString = [aceView string];
    NSString *tmpFilePath = [[NSWorkspace sharedWorkspace] createTempFileWithContents:manString];
    
    // run task "mandoc -T lint [tempFile]"
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:[[NSBundle mainBundle] pathForResource:@"mandoc" ofType:nil]];
    [task setArguments:@[@"-T", @"lint", tmpFilePath]];
    NSPipe *outputPipe = [NSPipe pipe];
    [task setStandardOutput:outputPipe];
    [task setStandardError:outputPipe];
    NSFileHandle *readHandle = [outputPipe fileHandleForReading];
    [task launch];
    [task waitUntilExit];
    [[NSFileManager defaultManager] removeItemAtPath:tmpFilePath error:nil];

    // read output into string
    NSString *outputStr = [[NSString alloc] initWithData:[readHandle readDataToEndOfFile]
                                                encoding:NSUTF8StringEncoding];
    if ([outputStr length] == 0 || outputStr == nil) {
        return @[];
    }
    
    NSArray *lines = [outputStr componentsSeparatedByString:@"\n"];
    NSMutableArray *annotations = [NSMutableArray array];
    
    // parse each line of output and create annotation dict
    for (NSString *line in lines) {
        if ([line length] == 0) {
            continue;
        }
        
        NSArray *components = [line componentsSeparatedByString:[NSString stringWithFormat:@"%@:", tmpFilePath]];
        if ([components count] < 2) {
            NSLog(@"Unable to parse output line: \"%@\"", line);
            continue;
        }
        
        NSString *warnString = components[1];
        NSArray *warnComponents = [warnString componentsSeparatedByString:@":"];
        if ([warnComponents count] < 2) {
            NSLog(@"Unable to parse output line: \"%@\"", line);
            continue;
        }
        
        NSNumber *row = @([warnComponents[0] intValue] - 1);
        NSNumber *col = @([warnComponents[1] intValue]);
        
        NSDictionary *annotation = @{ @"row": row,
                                      @"column": col,
                                      @"text": warnString,
                                      @"type": @"warning" };
        
        [annotations addObject:annotation];
    }
    
    return annotations;
}

#pragma mark - Load templates

- (IBAction)loadManMdocTemplate:(id)sender {
    NSString *str = [NSString stringWithContentsOfFile:kMdocTemplatePath
                                              encoding:NSUTF8StringEncoding
                                                 error:nil];
    [aceView setString:str];
}

- (IBAction)loadDefaultManTemplate:(id)sender {
    NSString *defaultManPath = [[NSBundle mainBundle] pathForResource:@"default.man" ofType:nil];
    NSString *str = [NSString stringWithContentsOfFile:defaultManPath
                                              encoding:NSUTF8StringEncoding
                                                 error:nil];
    [aceView setString:str];
}

@end
