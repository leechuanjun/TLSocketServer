//
//  ViewController.m
//  TLSocketServer
//
//  Created by lichuanjun on 15/9/29.
//  Copyright © 2015年 lichuanjun. All rights reserved.
//

#import "ViewController.h"

#define WELCOME_MSG  0
#define ECHO_MSG     1
#define WARNING_MSG  2

#define READ_TIMEOUT 15.0
#define READ_TIMEOUT_EXTENSION 10.0

#define FORMAT(format, ...) [NSString stringWithFormat:(format), ##__VA_ARGS__]


@interface ViewController ()
{
    AsyncSocket *listenSocket;
    NSMutableArray *connectedSockets;
    
    BOOL isRunning;
}
@property (weak) IBOutlet NSTextField *portTextField;
@property (weak) IBOutlet NSButton *startStopButton;
@property (unsafe_unretained) IBOutlet NSTextView *logTextView;

- (IBAction)startStopTap:(id)sender;

- (void)logError:(NSString *)msg;
- (void)logInfo:(NSString *)msg;
- (void)logMessage:(NSString *)msg;

@end

@implementation ViewController


-(void)viewWillAppear {
    [super viewDidAppear];
    // Do any additional setup after loading the view.
    [self.logTextView setString:@""];
    [self.portTextField setStringValue:@"22533"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    listenSocket = [[AsyncSocket alloc] initWithDelegate:self];
    connectedSockets = [[NSMutableArray alloc] initWithCapacity:10];
    
    isRunning = NO;
    
    [listenSocket setRunLoopModes:[NSArray arrayWithObject:NSRunLoopCommonModes]];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

#pragma mark - log

- (void)scrollToBottom
{
    NSScrollView *scrollView = [self.logTextView enclosingScrollView];
    NSPoint newScrollOrigin;
    
    if ([[scrollView documentView] isFlipped])
        newScrollOrigin = NSMakePoint(0.0F, NSMaxY([[scrollView documentView] frame]));
    else
        newScrollOrigin = NSMakePoint(0.0F, 0.0F);
    
    [[scrollView documentView] scrollPoint:newScrollOrigin];
}

- (void)logError:(NSString *)msg
{
    NSString *paragraph = [NSString stringWithFormat:@"%@\n", msg];
    
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:1];
    [attributes setObject:[NSColor redColor] forKey:NSForegroundColorAttributeName];
    
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
    
    [[self.logTextView textStorage] appendAttributedString:as];
    [self scrollToBottom];
}

- (void)logInfo:(NSString *)msg
{
    NSString *paragraph = [NSString stringWithFormat:@"%@\n", msg];
    
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:1];
    [attributes setObject:[NSColor purpleColor] forKey:NSForegroundColorAttributeName];
    
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
    
    [[self.logTextView textStorage] appendAttributedString:as];
    [self scrollToBottom];
}

- (void)logMessage:(NSString *)msg
{
    NSString *paragraph = [NSString stringWithFormat:@"%@\n", msg];
    
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:1];
    [attributes setObject:[NSColor blackColor] forKey:NSForegroundColorAttributeName];
    
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:paragraph attributes:attributes];
    
    [[self.logTextView textStorage] appendAttributedString:as];
    [self scrollToBottom];
}

#pragma mark - action handle event

- (IBAction)startStopTap:(id)sender {
    if(!isRunning)
    {
        int port = [self.portTextField intValue];
        
        if(port < 0 || port > 65535)
        {
            port = 0;
        }
        
        NSError *error = nil;
        if(![listenSocket acceptOnPort:port error:&error])
        {
            [self logError:FORMAT(@"Error starting server: %@", error)];
            return;
        }
        
        [self logInfo:FORMAT(@"TLSocket Server started on port %hu", [listenSocket localPort])];
        isRunning = YES;
        
        [self.portTextField setEnabled:NO];
        [self.startStopButton setTitle:@"Stop"];
    }
    else
    {
        // Stop accepting connections
        [listenSocket disconnect];
        
        // Stop any client connections
        NSUInteger i;
        for(i = 0; i < [connectedSockets count]; i++)
        {
            // Call disconnect on the socket,
            // which will invoke the onSocketDidDisconnect: method,
            // which will remove the socket from the list.
            [[connectedSockets objectAtIndex:i] disconnect];
        }
        
        [self logInfo:@"Stopped TLSocket Server"];
        isRunning = false;
        
        [self.portTextField setEnabled:YES];
        [self.startStopButton setTitle:@"Start"];
    }

}

#pragma mark - socket Delegate

- (void)onSocket:(AsyncSocket *)sock didAcceptNewSocket:(AsyncSocket *)newSocket
{
    [connectedSockets addObject:newSocket];
}

- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
    [self logInfo:FORMAT(@"Accepted client %@:%hu", host, port)];
    
    NSString *welcomeMsg = @"Welcome to the AsyncSocket TLSocket Server\r\n";
    NSData *welcomeData = [welcomeMsg dataUsingEncoding:NSUTF8StringEncoding];
    
    [sock writeData:welcomeData withTimeout:-1 tag:WELCOME_MSG];
    
    [sock readDataToData:[AsyncSocket CRLFData] withTimeout:READ_TIMEOUT tag:0];
}

- (void)onSocket:(AsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    if(tag == ECHO_MSG)
    {
        [sock readDataToData:[AsyncSocket CRLFData] withTimeout:READ_TIMEOUT tag:0];
    }
}

- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    NSData *strData = [data subdataWithRange:NSMakeRange(0, [data length] - 2)];
    NSString *msg = [[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding];
    if(msg)
    {
        [self logMessage:msg];
    }
    else
    {
        [self logError:@"Error converting received data into UTF-8 String"];
    }
    
    // Even if we were unable to write the incoming data to the log,
    // we're still going to echo it back to the client.
    [sock writeData:data withTimeout:-1 tag:ECHO_MSG];
}

/**
 * This method is called if a read has timed out.
 * It allows us to optionally extend the timeout.
 * We use this method to issue a warning to the user prior to disconnecting them.
 **/
- (NSTimeInterval)onSocket:(AsyncSocket *)sock
  shouldTimeoutReadWithTag:(long)tag
                   elapsed:(NSTimeInterval)elapsed
                 bytesDone:(NSUInteger)length
{
    if(elapsed <= READ_TIMEOUT)
    {
        NSString *warningMsg = @"Are you still there?\r\n";
        NSData *warningData = [warningMsg dataUsingEncoding:NSUTF8StringEncoding];
        
        [sock writeData:warningData withTimeout:-1 tag:WARNING_MSG];
        
        return READ_TIMEOUT_EXTENSION;
    }
    
    return 0.0;
}

- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err
{
    [self logInfo:FORMAT(@"Client Disconnected: %@:%hu", [sock connectedHost], [sock connectedPort])];
}

- (void)onSocketDidDisconnect:(AsyncSocket *)sock
{
    [connectedSockets removeObject:sock];
}

@end
