/*
 Copyright 2009-2014 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binaryform must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided withthe distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "UAUser+Internal.h"
#import "UAUserAPIClient.h"
#import "UAPush.h"
#import "UAUtils.h"
#import "UAConfig.h"
#import "UAKeychainUtils.h"
#import "UAPreferenceDataStore.h"
#import "UAirship.h"

NSString * const UAUserCreatedNotification = @"com.urbanairship.notification.user_created";

@interface UAUser()
@property (nonatomic, strong) UAPush *push;
@end

@implementation UAUser

+ (UAUser *)defaultUser {
    return [UAirship inboxUser];
}

+ (void)setDefaultUsername:(NSString *)defaultUsername withPassword:(NSString *)defaultPassword {

    NSString *storedUsername = [UAKeychainUtils getUsername:[UAirship shared].config.appKey];
    
    // If the keychain username is present a user already exists, if not, save
    if (storedUsername == nil) {
        //Store un/pw
        [UAKeychainUtils createKeychainValueForUsername:defaultUsername withPassword:defaultPassword forIdentifier:[UAirship shared].config.appKey];
    }
    
}

- (void)dealloc {
    [self unregisterForDeviceRegistrationChanges];
}

- (instancetype)initWithPush:(UAPush *)push config:(UAConfig *)config dataStore:(UAPreferenceDataStore *)dataStore {
    self = [super init];
    if (self) {
        self.config = config;
        self.apiClient = [UAUserAPIClient clientWithConfig:config];
        self.userUpdateBackgroundTask = UIBackgroundTaskInvalid;
        self.dataStore = dataStore;
        self.push = push;


        NSString *storedUsername = [UAKeychainUtils getUsername:self.config.appKey];
        NSString *storedPassword = [UAKeychainUtils getPassword:self.config.appKey];

        if (storedUsername && storedPassword) {
            self.username = storedUsername;
            self.password = storedPassword;
            [[NSUserDefaults standardUserDefaults] setObject:self.username forKey:@"ua_user_id"];
        }

        [self registerForDeviceRegistrationChanges];
    }
    
    return self;
}

+ (instancetype)userWithPush:(UAPush *)push config:(UAConfig *)config dataStore:(UAPreferenceDataStore *)dataStore {
    return [[UAUser alloc] initWithPush:push config:config dataStore:dataStore];
}

#pragma mark -
#pragma mark Update/Save User Data

/*
 saveUserData - Saves all the existing password and username data to disk.
 */
- (void)saveUserData {

    NSString *storedUsername = [UAKeychainUtils getUsername:self.config.appKey];

    if (!storedUsername) {

        // No username object stored in the keychain for this app, so let's create it
        // but only if we indeed have a username and password to store
        if (self.username != nil && self.password != nil) {
            if (![UAKeychainUtils createKeychainValueForUsername:self.username withPassword:self.password forIdentifier:self.config.appKey]) {
                UA_LERR(@"Save failed: unable to create keychain for username.");
                return;
            }
        } else {
            UA_LDEBUG(@"Save failed: must have a username and password.");
            return;
        }
    }
    
    //Update keychain with latest username and password
    [UAKeychainUtils updateKeychainValueForUsername:self.username
                                       withPassword:self.password
                                      forIdentifier:self.config.appKey];
    
    NSDictionary *dictionary = [self.dataStore objectForKey:self.config.appKey];
    NSMutableDictionary *userDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionary];

    [userDictionary setValue:self.url forKey:kUserUrlKey];


    // Save in defaults for access with a Settings bundle
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.username forKey:@"ua_user_id"];
    [defaults setObject:userDictionary forKey:self.config.appKey];
    [defaults synchronize];
}

#pragma mark -
#pragma mark Create

- (BOOL)isCreated {
    if (self.password.length && self.username.length) {
        return YES;
    }
    return NO;
}

- (void)sendUserCreatedNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:UAUserCreatedNotification object:nil];
}

- (void)createUser {
    if (self.isCreated) {
        return;
    }

    self.creatingUser = YES;


    UAUserAPIClientCreateSuccessBlock success = ^(UAUserData *data, NSDictionary *payload) {
        UA_LINFO(@"Created user %@.", data.username);

        self.creatingUser = NO;
        self.username = data.username;
        self.password = data.password;
        self.url = data.url;

        [self saveUserData];

        //if we didnt send a device token or a channel on creation, try again
        if (![payload valueForKey:@"device_tokens"] || ![payload valueForKey:@"ios_channels"]) {
            [self updateUser];
        }

        [self sendUserCreatedNotification];
    };

    UAUserAPIClientFailureBlock failure = ^(UAHTTPRequest *request) {
        UA_LINFO(@"Failed to create user");
        self.creatingUser = NO;
    };


    [self.apiClient createUserWithChannelID:self.push.channelID
                                deviceToken:self.push.deviceToken
                                  onSuccess:success
                                  onFailure:failure];
}

#pragma mark -
#pragma mark Update

-(void)updateUser {
    NSString *deviceToken = self.push.deviceToken;
    NSString *channelID = self.push.channelID;

    if (!self.isCreated) {
        UA_LDEBUG(@"Skipping user update, user not created yet.");
        return;
    }

    if (!channelID && !deviceToken) {
        UA_LDEBUG(@"Skipping user update, no device token or channel.");
        return;
    }


    if (self.userUpdateBackgroundTask == UIBackgroundTaskInvalid) {
        self.userUpdateBackgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            [self invalidateUserUpdateBackgroundTask];
        }];
    }

    [self.apiClient updateUser:self
                   deviceToken:deviceToken
                     channelID:channelID
                     onSuccess:^{
                         UA_LINFO(@"Updated user %@ successfully.", self.username);
                         [self invalidateUserUpdateBackgroundTask];
                     }
                     onFailure:^(UAHTTPRequest *request) {
                         UA_LDEBUG(@"Failed to update user.");
                         [self invalidateUserUpdateBackgroundTask];
                     }];
}

- (void)invalidateUserUpdateBackgroundTask {
    if (self.userUpdateBackgroundTask != UIBackgroundTaskInvalid) {
        UA_LTRACE(@"Ending user update background task %lu.", (unsigned long)self.userUpdateBackgroundTask);

        [[UIApplication sharedApplication] endBackgroundTask:self.userUpdateBackgroundTask];
        self.userUpdateBackgroundTask = UIBackgroundTaskInvalid;
    }
}


#pragma mark -
#pragma mark Device Token Listener

- (void)registerForDeviceRegistrationChanges {
    if (self.isObservingDeviceRegistrationChanges) {
        return;
    }
    
    self.isObservingDeviceRegistrationChanges = YES;

    // Listen for changes to the device token and channel ID
    [self.push addObserver:self forKeyPath:@"deviceToken" options:0 context:NULL];
    [self.push addObserver:self forKeyPath:@"channelID" options:0 context:NULL];

    // Update the user if we already have a channelID or device token
    if (self.push.deviceToken || self.push.channelID) {
        [self updateUser];
        return;
    }
}

-(void)observeValueForKeyPath:(NSString *)keyPath
                     ofObject:(id)object
                       change:(NSDictionary *)change
                      context:(void *)context {
    
    if ([keyPath isEqualToString:@"deviceToken"]) {
        // Only update user if we do not have a channel ID
        if (!self.push.channelID) {
            UA_LTRACE(@"KVO device token modified. Updating user.");
            [self updateUser];
        }
    } else if ([keyPath isEqualToString:@"channelID"]) {
        UA_LTRACE(@"KVO channel ID modified. Updating user.");
        [self updateUser];
    }
}

-(void)unregisterForDeviceRegistrationChanges {
    if (self.isObservingDeviceRegistrationChanges) {
        [self.push removeObserver:self forKeyPath:@"deviceToken"];
        [self.push removeObserver:self forKeyPath:@"channelID"];
        self.isObservingDeviceRegistrationChanges = NO;
    }
}

@end
