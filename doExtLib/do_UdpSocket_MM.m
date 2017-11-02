//
//  do_UdpSocket_MM.m
//  DoExt_MM
//
//  Created by @userName on @time.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import "do_UdpSocket_MM.h"

#import "doScriptEngineHelper.h"
#import "doIScriptEngine.h"
#import "doInvokeResult.h"
#import "doServiceContainer.h"
#import "doLogEngine.h"
#import "doJsonHelper.h"
#import "doIOHelper.h"
#import "doIPage.h"
#import "GCDAsyncUdpSocket.h"

#ifdef DEBUG
#ifndef ZJLog
#define ZJLog(fmt, ...) NSLog((@"%s [Line %d] "fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif
#else
#define ZJLog(...)
#endif

#define do_UdpSocketMaxPort 65535
#define do_UdpSocketMinPort 0

@interface do_UdpSocket_MM()<GCDAsyncUdpSocketDelegate>
@property (nonatomic, strong) GCDAsyncUdpSocket *udpSocket;
@property (nonatomic, strong) dispatch_queue_t udpSocketQueue; // 串行队列
@property (nonatomic, strong) NSString *callBackName;
@property (nonatomic, strong) id<doIScriptEngine> curScriptEngine;
@property (nonatomic, assign) long dataTag;

@end

@implementation do_UdpSocket_MM

#pragma mark - lazy
- (dispatch_queue_t)udpSocketQueue {
    if (_udpSocketQueue == nil) {
        _udpSocketQueue = dispatch_queue_create("com.do.do_UdpSocket", DISPATCH_QUEUE_SERIAL);
        return _udpSocketQueue;
    }
    return _udpSocketQueue;
}

- (GCDAsyncUdpSocket *)udpSocket {
    if (_udpSocket == nil) {
        _udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:self.udpSocketQueue];
        NSError *error;
        [_udpSocket enableBroadcast:true error:&error];
        if (error) {
            [[doServiceContainer Instance].LogEngine WriteError:nil :[NSString stringWithFormat:@"enableBroadcast failed: %@",error.description]];
        }
        return _udpSocket;
    }
    return _udpSocket;
}

#pragma mark - 注册属性（--属性定义--）
-(void)OnInit
{
    [super OnInit];
    //注册属性
    [self RegistProperty:[[doProperty alloc] init:@"localPort" :String :@"8888" :NO]];
    [self RegistProperty:[[doProperty alloc] init:@"serverIP" :String :@"" :NO]];
    [self RegistProperty:[[doProperty alloc] init:@"serverPort" :String :@"" :NO]];
    self.dataTag = 0;
}

//销毁所有的全局对象
-(void)Dispose
{
    _udpSocket = nil;
    _udpSocketQueue = nil;
    self.dataTag = 0;
}

#pragma mark - private
//得到二进制字符串
-(NSString *)getHexStr:(NSData *)data
{
    Byte *testByte = (Byte *)[data bytes];
    NSString *hexStr=@"";
    for(int i=0;i<[data length];i++)
    {
        NSString *newHexStr = [NSString stringWithFormat:@"%x",testByte[i]&0xff];///16进制数
        if([newHexStr length]==1)
        {
            hexStr = [NSString stringWithFormat:@"%@0%@",hexStr,newHexStr];
        }
        else
        {
            hexStr = [NSString stringWithFormat:@"%@%@",hexStr,newHexStr];
        }
    }
    return hexStr;
}

- (NSData *)convertHexStrToData:(NSString *)str {
    if (!str || [str length] == 0) {
        return nil;
    }
    
    NSMutableData *hexData = [[NSMutableData alloc] initWithCapacity:8];
    NSRange range;
    if ([str length] % 2 == 0) {
        range = NSMakeRange(0, 2);
    } else {
        range = NSMakeRange(0, 1);
    }
    for (NSInteger i = range.location; i < [str length]; i += 2) {
        unsigned int anInt;
        NSString *hexCharStr = [str substringWithRange:range];
        NSScanner *scanner = [[NSScanner alloc] initWithString:hexCharStr];
        
        [scanner scanHexInt:&anInt];
        NSData *entity = [[NSData alloc] initWithBytes:&anInt length:1];
        [hexData appendData:entity];
        
        range.location += range.length;
        range.length = 2;
    }
    return hexData;
}

/// 检查端口号是否合法
- (BOOL)checkPortLegalWithPortString:(NSString*)portString {
    if ([portString intValue] > do_UdpSocketMaxPort || [portString intValue] < do_UdpSocketMinPort) { // 端口号非法
        return false;
    }
    return true;
}

/// 检查Ip地址是否合法
- (BOOL)checkIPAddressLegalWithIPAddressString:(NSString*)ipAddressStr {
    NSString *pattern = @"\\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\b";
    NSRegularExpression *regular = [[NSRegularExpression alloc] initWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSArray *results = [regular matchesInString:ipAddressStr options:0 range:NSMakeRange(0, ipAddressStr.length)];
    return (results.count > 0);
}

/// 发送数据失败回调处理
- (void)failCallBackOfSendMethod {
    doInvokeResult *result = [[doInvokeResult alloc] init];
        [result SetResultBoolean:false];
    [self.curScriptEngine Callback:self.callBackName :result];
}

/// 发送数据成功回调处理
- (void)successCallBackOfSendMethod {
    doInvokeResult *result = [[doInvokeResult alloc] init];
        [result SetResultBoolean:true];
    [self.curScriptEngine Callback:self.callBackName :result];
}


#pragma mark -
#pragma mark - 同步异步方法的实现
//同步
- (void)open:(NSArray *)parms
{
    
    NSString *localPort = [self GetPropertyValue:@"localPort"];
    ZJLog(@"本地监听端口号: %@",localPort);
    if ([self checkPortLegalWithPortString:localPort]) {
        NSError *error = nil;
        if (![self.udpSocket bindToPort:localPort.intValue error:&error])
        {
            ZJLog(@"Error binding: %@", error);
            [[doServiceContainer Instance].LogEngine WriteError:nil :@"do_UdpSocket绑定本地监听端口号失败,该端口号可能已被占用"];
            return;
        }
        if (![self.udpSocket beginReceiving:&error])
        {
            ZJLog(@"Error receiving: %@", error);
            [[doServiceContainer Instance].LogEngine WriteError:nil :@"do_UdpSocket开始接受数据失败,端口号未绑定"];
            return;
        }
    }else {
        ZJLog(@"localport端口号超出范文");
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"do_UdpSocket localPort取值范围应为0~65535"];
        return;
    }
    
   
}

- (void)close:(NSArray *)parms
{
    [self.udpSocket pauseReceiving];
    [self.udpSocket close];
    self.udpSocket = nil;
}
//异步
- (void)send:(NSArray *)parms
{
    if (_udpSocket == nil){
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"do_UdpSocket未初始化或已关闭，请调用open方法初始化"];
        return;
    }
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    self.curScriptEngine = [parms objectAtIndex:1];
    self.callBackName = [parms objectAtIndex:2];
    
    
    NSString *type = [doJsonHelper GetOneText:_dictParas :@"type" :nil];
    NSString *content = [doJsonHelper GetOneText:_dictParas :@"content" :nil];
    
    if (type == nil) {
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"type参数必填"];
        [self failCallBackOfSendMethod];
        return;
    }
    if (content == nil) {
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"content参数必填"];
        [self failCallBackOfSendMethod];
        return;
    }
    
    NSString *serverIp = [self GetPropertyValue:@"serverIP"];
    NSString *serverPort = [self GetPropertyValue:@"serverPort"];
    if (![serverIp isEqualToString:@""]) { // ip赋值检查
        if ([self checkIPAddressLegalWithIPAddressString:serverIp]) { // 检车ip是否合法
            if (![serverPort isEqualToString:@""]) { // port赋值检查
                if ([self checkPortLegalWithPortString:serverPort]) { // port范围检查
                    
                    NSData *dataToWrite;
                    type = type.lowercaseString;
                    if ([type isEqualToString:@"utf-8"]) {
                        dataToWrite = [[NSData alloc]initWithBytes:[content UTF8String] length:[content lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
                    }else if ([type isEqualToString:@"gbk"]) {
                        NSStringEncoding gbkEncoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
                        dataToWrite = [content dataUsingEncoding:gbkEncoding];
                    }else if ([type isEqualToString:@"hex"]){
                        dataToWrite = [self convertHexStrToData:content];
                    }else if ([type isEqualToString:@"file"]) {
                        // 小文件数据传输
                        NSString *filePath = [doIOHelper GetLocalFileFullPath:self.curScriptEngine.CurrentPage.CurrentApp :content];
                        NSData *fileData = [NSData dataWithContentsOfFile:filePath];
                        if (fileData == nil) {
                            [[doServiceContainer Instance].LogEngine WriteError:nil :@"file对应的文件路径错误或资源不存在"];
                            [self failCallBackOfSendMethod];
                            return;
                        }else {
                            if (fileData.length >= 9216) {
                                [self failCallBackOfSendMethod];
                                [[doServiceContainer Instance].LogEngine WriteError:nil :@"文件数据超过9216个字节，udp send方法每次发送数据包最大为9216个字节"];
                                return;
                            }
                        }
                        
                        [self.udpSocket sendData:fileData toHost:serverIp port:serverPort.intValue withTimeout:-1 tag:self.dataTag];
                        self.dataTag ++;
                        return;
                        
                    }else {
                        [[doServiceContainer Instance].LogEngine WriteError:nil :@"发送数据格式错误"];
                        [self failCallBackOfSendMethod];
                        return;
                    }
                    
                    if (dataToWrite.length >= 9216) {
                        [self failCallBackOfSendMethod];
                        [[doServiceContainer Instance].LogEngine WriteError:nil :@"发送数据超过9216个字节，udp send方法每次发送数据包最大为9216个字节"];
                        return;
                    }
                    // 发送file除外的数据
                    [self.udpSocket sendData:dataToWrite toHost:serverIp port:serverPort.intValue withTimeout:-1 tag:self.dataTag];

                    self.dataTag++;
                    return;
                    
                }else {
                    ZJLog(@"serverPort取值范围应为0~65535");
                    [[doServiceContainer Instance].LogEngine WriteError:nil :@"do_UdpSocket serverPort取值范围应为0~65535"];
                    [self failCallBackOfSendMethod];
                }
            }else {
                ZJLog(@"serverPort未赋值");
                [[doServiceContainer Instance].LogEngine WriteError:nil :@"do_UdpSocket serverPort未赋值"];
                [self failCallBackOfSendMethod];
                return;
            }
            
        }else {
            ZJLog(@"serverIP不合法");
            [[doServiceContainer Instance].LogEngine WriteError:nil :@"do_UdpSocket serverIP不合法"];
            [self failCallBackOfSendMethod];
        }
        
    }else {
        ZJLog(@"serverIP未赋值");
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"do_UdpSocket serverIP未赋值"];
        [self failCallBackOfSendMethod];
        return;
    }

}

#pragma mark - GCDAsyncUdpSocketDelegate回调
- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag {
    [self successCallBackOfSendMethod];
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error {
    [[doServiceContainer Instance].LogEngine WriteError:nil :@"do_UdpSocket 发送数据失败, 可能原因: 发送数据超时或者发送数据过大"];
    [self failCallBackOfSendMethod];
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data
      fromAddress:(NSData *)address
withFilterContext:(nullable id)filterContext {
    NSString *ip = [sock connectedHost];
    uint16_t port = [sock connectedPort];
    ZJLog(@"ip: %@, port: %d",ip,port);
    doInvokeResult *invokeResult = [[doInvokeResult alloc]init];
    [invokeResult SetResultValue:[self getHexStr:data]];
    [self.EventCenter FireEvent:@"receive" :invokeResult];
}

@end
