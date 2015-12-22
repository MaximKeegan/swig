    //
//  SWAccount.m
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-21.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import "SWAccount.h"
#import "SWAccountConfiguration.h"
#import "SWEndpoint.h"
#import "SWCall.h"
#import "SWUriFormatter.h"
#import "NSString+PJString.h"

#import "pjsua.h"

#define kRegTimeout 800

@interface SWAccount ()

@property (nonatomic, strong) SWAccountConfiguration *configuration;
@property (nonatomic, strong) NSMutableArray *calls;

@end

@implementation SWAccount

-(instancetype)init {
    
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _calls = [NSMutableArray new];
    
    return self;
}

-(void)dealloc {
    
}

-(void)setAccountId:(NSInteger)accountId {
    
    _accountId = accountId;
}

-(void)setAccountState:(SWAccountState)accountState {
    
    [self willChangeValueForKey:@"accountState"];
    _accountState = accountState;
    [self didChangeValueForKey:@"accountState"];
}

-(void)setAccountConfiguration:(SWAccountConfiguration *)accountConfiguration {
    
    [self willChangeValueForKey:@"accountConfiguration"];
    _accountConfiguration = accountConfiguration;
    [self didChangeValueForKey:@"accountConfiguration"];
}

-(void)configure:(SWAccountConfiguration *)configuration completionHandler:(void(^)(NSError *error))handler {
    
    self.accountConfiguration = configuration;
    
    if (!self.accountConfiguration.address) {
        self.accountConfiguration.address = [SWAccountConfiguration addressFromUsername:self.accountConfiguration.username domain:self.accountConfiguration.domain];
    }
    
    NSString *suffix = @"";
    
    pjsua_transport_info transport_info;
    pjsua_transport_get_info(0, &transport_info);
    
    suffix = [NSString stringWithFormat:@";transport=%@", [NSString stringWithPJString:transport_info.type_name]];
    
    pjsua_acc_config acc_cfg;
    pjsua_acc_config_default(&acc_cfg);
    
    acc_cfg.id = [[SWUriFormatter sipUri:[self.accountConfiguration.address stringByAppendingString:suffix] withDisplayName:self.accountConfiguration.displayName] pjString];
    acc_cfg.reg_uri = [[SWUriFormatter sipUri:[self.accountConfiguration.domain stringByAppendingString:suffix]] pjString];
    acc_cfg.register_on_acc_add = self.accountConfiguration.registerOnAdd ? PJ_TRUE : PJ_FALSE;
    acc_cfg.publish_enabled = self.accountConfiguration.publishEnabled ? PJ_TRUE : PJ_FALSE;
    acc_cfg.reg_timeout = kRegTimeout;
//    acc_cfg.reg_delay_before_refresh
//    acc_cfg.reg_first_retry_interval
    acc_cfg.reg_retry_interval = 5;
    
    acc_cfg.cred_count = 1;
    acc_cfg.cred_info[0].scheme = [self.accountConfiguration.authScheme pjString];
    acc_cfg.cred_info[0].realm = [self.accountConfiguration.authRealm pjString];
    acc_cfg.cred_info[0].username = [self.accountConfiguration.username pjString];
    acc_cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    acc_cfg.cred_info[0].data = [self.accountConfiguration.password pjString];
    acc_cfg.ka_interval = 25;

    acc_cfg.sip_stun_use = PJSUA_STUN_USE_DEFAULT;
    acc_cfg.media_stun_use = PJSUA_STUN_USE_DEFAULT;
    
    if (!self.accountConfiguration.proxy) {
        acc_cfg.proxy_cnt = 0;
    } else {
        acc_cfg.proxy_cnt = 1;
        acc_cfg.proxy[0] = [[SWUriFormatter sipUri:[self.accountConfiguration.proxy stringByAppendingString:suffix]] pjString];
    }
    
    
    pj_status_t status;
    
    int accountId = (int)self.accountId;
    
    status = pjsua_acc_add(&acc_cfg, PJ_TRUE, &accountId);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error adding account" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    } else {
        [[SWEndpoint sharedEndpoint] addAccount:self];
    }
    
    if (!self.accountConfiguration.registerOnAdd) {
        [self connect:handler];
    } else {
        if (handler) {
            handler(nil);
        }
    }
}

- (void) setCode: (NSString *) code completionHandler:(void(^)(NSError *error))handler {
    if ([code length] == 4) {
        [self.accountConfiguration setCode:code];
        [self connect:^(NSError *error) {
            handler(error);
        }];

        return;
    }
    NSError *error = [NSError errorWithDomain:@"Code invalid" code:0 userInfo:nil];
    if (handler) {
        handler(error);
    }
}

- (void) setPhone: (NSString *) phone completionHandler:(void(^)(NSError *error))handler {
    self.accountConfiguration.username = phone;
    pjsua_acc_config acc_cfg;
    pj_status_t status = pjsua_acc_get_config((int)self.accountId, [[SWEndpoint sharedEndpoint] pjPool], &acc_cfg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Cannot get config" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        return;
    }
    
    acc_cfg.cred_info[0].username = [phone pjString];
    
    status = pjsua_acc_modify((int)self.accountId, &acc_cfg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Cannot modify account" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        return;
    }
    
    
    if (handler) {
        handler(nil);
    }
    return;
}

-(void)connect:(void(^)(NSError *error))handler {
    
    //FIX: registering too often will cause the server to possibly return error
        
    pj_status_t status;
    
    status = pjsua_acc_set_registration((int)self.accountId, PJ_TRUE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting registration" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    status = pjsua_acc_set_online_status((int)self.accountId, PJ_TRUE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting online status" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    if (handler) {
        handler(nil);
    }
}

-(void)disconnect:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    
    status = pjsua_acc_set_online_status((int)self.accountId, PJ_FALSE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting online status" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    status = pjsua_acc_set_registration((int)self.accountId, PJ_FALSE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting registration" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    if (handler) {
        handler(nil);
    }
}

-(void)accountStateChanged {
    
    pjsua_acc_info accountInfo;
    pjsua_acc_get_info((int)self.accountId, &accountInfo);
    
    pjsip_status_code code = accountInfo.status;
    
    //TODO make status offline/online instead of offline/connect
    //status would be disconnected, online, and offline, isConnected could return true if online/offline
    
    if (code == 0 || accountInfo.expires == -1) {
        self.accountState = SWAccountStateDisconnected;
    }
    
    else if (PJSIP_IS_STATUS_IN_CLASS(code, 100) || PJSIP_IS_STATUS_IN_CLASS(code, 300)) {
        self.accountState = SWAccountStateConnecting;
    }
    
    else if (PJSIP_IS_STATUS_IN_CLASS(code, 200)) {
        self.accountState = SWAccountStateConnected;
    }
    
    else {
        self.accountState = SWAccountStateDisconnected;
    }
}

-(BOOL)isValid {
    
    return pjsua_acc_is_valid((int)self.accountId);
}

#pragma Call Management

-(void)addCall:(SWCall *)call {
    
    [self.calls addObject:call];
    
    //TODO:: setup blocks
}

-(void)removeCall:(NSUInteger)callId {
    
    SWCall *call = [self lookupCall:callId];
    
    if (call) {
        [self.calls removeObject:call];
    }
    
    call = nil;
}

-(SWCall *)lookupCall:(NSInteger)callId {
    
    NSUInteger callIndex = [self.calls indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        
        SWCall *call = (SWCall *)obj;
        
        if (call.callId == callId && call.callId != PJSUA_INVALID_ID) {
            return YES;
        }
        
        return NO;
    }];
    
    if (callIndex != NSNotFound) {
        return [self.calls objectAtIndex:callIndex]; //TODO add more management
    }
    
    else {
        return nil;
    }
}

-(SWCall *)firstCall {
    
    if (self.calls.count > 0) {
        return self.calls[0];
    }
    
    else {
        return nil;
    }
}

-(void)endAllCalls {
    
    for (SWCall *call in self.calls) {
        [call hangup:nil];
    }
}

-(void)makeCall:(NSString *)URI completionHandler:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    NSError *error;
    
    pjsua_call_id callIdentifier;
//    pj_str_t uri = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];
    
    pj_str_t uri = [[SWUriFormatter sipUriWithPhone:URI fromAccount:self toGSM:YES] pjString];
    
    status = pjsua_call_make_call((int)self.accountId, &uri, 0, NULL, NULL, &callIdentifier);
    
    if (status != PJ_SUCCESS) {
        
        error = [NSError errorWithDomain:@"Error hanging up call" code:0 userInfo:nil];
    }
    
    else {
        
        SWCall *call = [SWCall callWithId:callIdentifier accountId:self.accountId inBound:NO];

        
        [self addCall:call];
    }
    
    if (handler) {
        handler(error);
    }
}

-(void)sendMessage:(NSString *)message to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer))handler {
    [self sendMessage:message fileType:SWFileTypeNo fileHash:nil to:URI isGroup:NO completionHandler:handler];
}

-(void)sendGroupMessage:(NSString *)message to:(NSString *)URI completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer))handler {
    [self sendMessage:message fileType:SWFileTypeNo fileHash:nil to:URI isGroup:YES completionHandler:handler];
}


-(void)sendMessage:(NSString *)message fileType:(SWFileType) fileType fileHash:(NSString *) fileHash to:(NSString *)URI isGroup:(BOOL) isGroup completionHandler:(void(^)(NSError *error, NSString *SMID, NSString *fileServer))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;

    pj_str_t to = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];
    
    status = pjsua_acc_create_request((int)self.accountId, &pjsip_message_method, &to, &tx_msg);
    
    pjsip_via_hdr *via_hdr = pjsip_msg_find_hdr(tx_msg->msg, PJSIP_H_VIA, NULL);
    via_hdr->branch_param = pj_str((char *)"z9hG4bK");
    via_hdr->comment = pj_str((char *)"How to remove Branch?");
    pjsip_msg_find_remove_hdr(tx_msg->msg, PJSIP_H_VIA, NULL);
    
    pjsip_msg_add_hdr(tx_msg->msg, via_hdr);


    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Error creating message" code:0 userInfo:nil];
        handler(error, nil, nil);
        return;
    }

    pj_str_t pjMessage = [message pjString];
    
    pj_str_t type = pj_str((char *)"text");
    pj_str_t subtype = pj_str((char *)"plain");
    
    pjsip_msg_body *body = pjsip_msg_body_create([SWEndpoint sharedEndpoint].pjPool, &type, &subtype, &pjMessage);
    
    tx_msg->msg->body = body;
    
    if (isGroup) {
        pj_str_t hname = pj_str((char *)"GroupID");
        pj_str_t hvalue = [URI pjString];
        pjsip_generic_string_hdr *group_id_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
        
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)group_id_hdr);
    }
    
    if (fileType != SWFileTypeNo) {
        pj_str_t hname = pj_str((char *)"FileType");
        char to_string[256];
        pj_str_t hvalue;
        hvalue.ptr = to_string;
        hvalue.slen = sprintf(to_string, "%lu",(unsigned long)fileType);
        pjsip_generic_string_hdr* filetype_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
        
        hname = pj_str((char *)"FileHash");
        
        hvalue = [fileHash pjString];

        pjsip_generic_string_hdr* file_hash_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
        
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)filetype_hdr);
        pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)file_hash_hdr);
    }
    
//    pjsip_cid_hdr *cid_hdr = PJSIP_MSG_CID_HDR(tx_msg->msg);
//

//    pjsip_msg_find_remove_hdr(tx_msg->msg, PJSIP_H_CSEQ, NULL);
//    
//    pjsip_cseq_hdr *csec_hdr = pjsip_cseq_hdr_create([SWEndpoint sharedEndpoint].pjPool);
//    csec_hdr->cseq = 1;
//    csec_hdr->method = pjsip_message_method;
//    
//    pjsip_msg_add_hdr(tx_msg->msg, csec_hdr);
//    
//    pjsip_to_hdr *from_hdr = PJSIP_MSG_FROM_HDR(tx_msg->msg);
//    from_hdr->tag = pj_str((char *)"");
//
//    pjsip_msg_find_remove_hdr(tx_msg->msg, PJSIP_H_FROM, NULL);
//    pjsip_msg_add_hdr(tx_msg->msg, from_hdr);

    
    
    
    
    status = pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &sendMessageCallback);
//    status = pjsip_endpt_send_request_stateless(pjsua_get_pjsip_endpt(), tx_msg, NULL, &sendMessageCallback);
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Error sending message" code:0 userInfo:nil];
        handler(error, nil, nil);
        return;
    }
    
//    handler(nil, [NSString stringWithPJString:cid_hdr->id]);
}

static void sendMessageCallback(void *token, pjsip_event *e) {
    NSLog(@"sendMessageCallback");
//    return;
    void (^handler)(NSError *, NSString *, NSString *) = (__bridge_transfer typeof(handler))(token);
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;

    NSError *error = [NSError errorWithDomain:@"Failed to SendMessage" code:0 userInfo:nil];
    if (msg == nil) {
        handler(error, nil, nil);
        return;
    }
    pj_str_t smid_hdr_str = pj_str((char *)"SMID");
    pjsip_generic_string_hdr *smid_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(msg, &smid_hdr_str, nil);
    
    NSString *fileServer = nil;
    pj_str_t  file_server_hdr_str = pj_str((char *)"File-Server");
    pjsip_generic_string_hdr* file_server_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(msg, &file_server_hdr_str, nil);
    if (file_server_hdr != nil) {
        fileServer = [[NSString stringWithPJString:file_server_hdr->hvalue] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    }
    
    if (smid_hdr) {
        handler(nil, [NSString stringWithPJString:smid_hdr->hvalue], fileServer);
    } else {
        NSError *error = [NSError errorWithDomain:@"Failed to SendMessage" code:0 userInfo:nil];
        handler(error, nil, nil);
    }
}


-(void)sendMessageReadNotifyTo:(NSString *)URI smid:(NSUInteger)smid completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t hname = pj_str((char *)"Event");
    char to_string[256];
    pj_str_t hvalue;
    hvalue.ptr = to_string;
    hvalue.slen = sprintf(to_string, "%lu",(unsigned long)SWMessageStatusRead);
    
    pj_pool_t *tempPool = pjsua_pool_create("swig-pjsua-temp", 512, 512);

    
    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create(tempPool, &hname, &hvalue);
    
    hname = pj_str((char *)"SMID");
    hvalue.ptr = to_string;
    hvalue.slen = sprintf(to_string, "%lu",(unsigned long)smid);
    pjsip_generic_string_hdr* smid_hdr = pjsip_generic_string_hdr_create(tempPool, &hname, &hvalue);

    
    pjsua_transport_info transport_info;
    pjsua_transport_get_info(0, &transport_info);
    
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
//    pjsip_sip_uri *to = (pjsip_sip_uri *)pjsip_uri_get_uri(data->msg_info.to->uri);
//    pjsip_sip_uri *from = (pjsip_sip_uri *)pjsip_uri_get_uri(data->msg_info.from->uri);
    
//    char to_string[256];
//    char from_string[256];
//    
//    pj_str_t source;
//    source.ptr = to_string;
//    source.slen = snprintf(to_string, 256, "sip:%.*s@%.*s", (int)to->user.slen, to->user.ptr, (int)to->host.slen,to->host.ptr);
//    
//    pj_str_t target;
//    target.ptr = from_string;
//    target.slen = snprintf(from_string, 256, "sip:%.*s@%.*s", (int)from->user.slen, from->user.ptr, (int)from->host.slen,from->host.ptr);

    pj_str_t target = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];


    
    /* Создаем непосредственно запрос */
    
    //TODO: Контакт не нужен!
    status = pjsip_endpt_create_request(pjsua_get_pjsip_endpt(),
                                        &pjsip_notify_method,
                                        &info.acc_uri, //proxy
                                        &info.acc_uri, //from
                                        &target, //to
                                        &info.acc_uri, //contact
                                        NULL,
                                        -1,
                                        NULL,
                                        &tx_msg);
    

    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create reading recepient" code:0 userInfo:nil];
        handler(error);
        pj_pool_release(tempPool);
    
        return;
    }
    
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)smid_hdr);
    
    if (status == PJ_SUCCESS) {
        pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, NULL, NULL);
    }
    pj_pool_release(tempPool);

}

-(void)setPresenseStatusOnline:(SWPresenseState) state completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t hname = pj_str((char *)"Event");
    
    char to_string[256];
    pj_str_t hvalue;
    hvalue.ptr = to_string;
    hvalue.slen = sprintf(to_string, "%lu",(unsigned long)state);
    
    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
    
    pjsua_transport_info transport_info;
    pjsua_transport_get_info(0, &transport_info);
    
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    /* Создаем непосредственно запрос */
    status = pjsip_endpt_create_request(pjsua_get_pjsip_endpt(),
                                        &pjsip_publish_method,
                                        &info.acc_uri, //proxy
                                        &info.acc_uri, //from
                                        &info.acc_uri, //to
                                        &info.acc_uri, //contact
                                        NULL,
                                        -1,
                                        NULL,
                                        &tx_msg);
    
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create publish status" code:0 userInfo:nil];
        handler(error);
        
        return;
    }
    
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    
    if (status == PJ_SUCCESS) {
        pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, NULL, NULL);
    }

    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to publish status" code:0 userInfo:nil];
        handler(error);
        
        return;
    }
}

-(void)subscribeBuddyURI:(NSString *) URI completionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t hname = pj_str((char *)"Event");
    
    pj_str_t hvalue = pj_str((char *)"presence");
    
    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pj_str_t target = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];
    
    /* Создаем непосредственно запрос */
    status = pjsip_endpt_create_request(pjsua_get_pjsip_endpt(),
                                        &pjsip_subscribe_method,
                                        &info.acc_uri, //proxy
                                        &info.acc_uri, //from
                                        &target, //to
                                        &info.acc_uri, //contact
                                        NULL,
                                        -1,
                                        NULL,
                                        &tx_msg);
    
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create subscribe request" code:0 userInfo:nil];
        handler(error);
        
        return;
    }
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    
    if (status == PJ_SUCCESS) {
        pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, NULL, NULL);
    }
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to send subscribe requesrt" code:0 userInfo:nil];
        handler(error);
        
        return;
    }
}

-(void)updateBalanceCompletionHandler:(void(^)(NSError *error))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t hname = pj_str((char *)"Command-Name");
    
    pj_str_t hvalue = pj_str((char *)"GetBalance");
    
    pjsip_generic_string_hdr* event_hdr = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname, &hvalue);
    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create balance request" code:0 userInfo:nil];
        handler(error);
        
        return;
    }
    
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)event_hdr);
    
    if (status == PJ_SUCCESS) {
        pjsip_endpt_send_request_stateless(pjsua_get_pjsip_endpt(), tx_msg, NULL, NULL);
    }
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to send balance request" code:0 userInfo:nil];
        handler(error);
        
        return;
    }

}

-(void) createGroup:(NSArray *) abonents name:(NSString *) name CompletionHandler:(void(^)(NSError *error, NSString *groupID))handler {
    pj_status_t    status;
    pjsip_tx_data *tx_msg;
    
    pj_str_t hname_name = pj_str((char *)"Command-Name");
    pj_str_t hvalue_name = pj_str((char *)"CreateChat");
    pjsip_generic_string_hdr* hdr_name = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname_name, &hvalue_name);

    pj_str_t hname_value = pj_str((char *)"Command-Value");
    pj_str_t hvalue_value = [name pjString];
    pjsip_generic_string_hdr* hdr_value = pjsip_generic_string_hdr_create([SWEndpoint sharedEndpoint].pjPool, &hname_value, &hvalue_value);

    
    pjsua_acc_info info;
    
    pjsua_acc_get_info((int)self.accountId, &info);
    
    pjsip_method method;
    pj_str_t method_string = pj_str("COMMAND");
    
    pjsip_method_init_np(&method, &method_string);
    
    /* Создаем непосредственно запрос */
    status = pjsua_acc_create_request((int)self.accountId, &method, &info.acc_uri, &tx_msg);
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to create balance request" code:0 userInfo:nil];
        handler(error, nil);
        
        return;
    }
    
    NSString *abonentsString = [abonents componentsJoinedByString:@", "];
    
    pj_str_t abonentsPjStr = [abonentsString pjString];
    
    pj_str_t type = pj_str((char *)"text");
    pj_str_t subtype = pj_str((char *)"plain");
    
    
    pjsip_msg_body *body = pjsip_msg_body_create([SWEndpoint sharedEndpoint].pjPool, &type, &subtype, &abonentsPjStr);
    
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_name);
    pjsip_msg_add_hdr(tx_msg->msg, (pjsip_hdr*)hdr_value);
    tx_msg->msg->body = body;
    
    if (status == PJ_SUCCESS) {
        status = pjsip_endpt_send_request(pjsua_get_pjsip_endpt(), tx_msg, 1000, (__bridge_retained void *) [handler copy], &createChatCallback);
    }
    
    if (status != PJ_SUCCESS) {
        NSError *error = [NSError errorWithDomain:@"Failed to send balance request" code:0 userInfo:nil];
        handler(error, nil);
        
        return;
    }
    
}

static void createChatCallback(void *token, pjsip_event *e) {

    void (^handler)(NSError *, NSString *) = (__bridge_transfer typeof(handler))(token);
    
    pjsip_msg *msg = e->body.rx_msg.rdata->msg_info.msg;
    
    pj_str_t group_id_hdr_str = pj_str((char *)"GroupID");
    pjsip_generic_string_hdr *group_id_hdr = (pjsip_generic_string_hdr*)pjsip_msg_find_hdr_by_name(msg, &group_id_hdr_str, nil);
    if (group_id_hdr) {
        handler(nil, [NSString stringWithPJString:group_id_hdr->hvalue]);
    } else {
        NSError *error = [NSError errorWithDomain:@"Failed to create group" code:0 userInfo:nil];
        handler(error, nil);
    }
}


@end