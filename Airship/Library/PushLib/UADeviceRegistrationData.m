
#import "UADeviceRegistrationData.h"

@interface UADeviceRegistrationData()

@property(nonatomic, copy) NSString *deviceToken;
@property(nonatomic, retain) NSDictionary *payload;
@property(nonatomic, assign) BOOL pushEnabled;

@end

@implementation UADeviceRegistrationData

- (id)initWithDeviceToken:(NSString *)token withPayload:(NSDictionary *)payload pushEnabled:(BOOL)enabled {
    if (self = [super init]) {
        self.deviceToken = token;
        self.payload = payload;
        self.pushEnabled = enabled;
    }
    return self;
}

+ (id)dataWithDeviceToken:(NSString *)token withPayload:(NSDictionary *)payload pushEnabled:(BOOL)enabled {
    return [[[UADeviceRegistrationData alloc] initWithDeviceToken:token withPayload:payload pushEnabled:enabled] autorelease];
}

- (void)dealloc {
    self.deviceToken = nil;
    self.payload = nil;
    [super dealloc];
}

#pragma mark - 
#pragma mark - NSObject overrides

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[UADeviceRegistrationData class]]) {
        UADeviceRegistrationData *other = (UADeviceRegistrationData *)object;
        return [self.deviceToken isEqualToString:other.deviceToken] &&
        [self.payload isEqual:other.payload] &&
        self.pushEnabled == other.pushEnabled;
    } else {
        return NO;
    }
}

//Note: this is a fairly naive hash combination, but should be sufficient for our purposes, since
//the types here are asymmetric
- (NSUInteger)hash {
    return [self.deviceToken hash] ^ [self.payload hash] ^ self.pushEnabled;
}

@end
