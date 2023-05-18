//
//  Feed+Faye.swift
//  GetStream-iOS
//
//  Created by Alexey Bukhtin on 18/02/2019.
//  Copyright © 2019 Stream.io Inc. All rights reserved.
//

import Foundation
import Faye

public typealias Subscription<T: ActivityProtocol> = (_ result: Result<SubscriptionResponse<T>, SubscriptionError>) -> Void

public typealias SubscriptionResult = (_ result: Result<LiveResponse, SubscriptionError>) -> Void

public enum SubscriptionError: Error {
    case fayeClient(_ error: Faye.Client.Error)
    case decoding(_ error: DecodingError)
    case unexpected(_ error: Error)
}

extension Feed {
    
    /// Subscribe for the updates of the given activity type of `ActivityProtocol`.
    ///
    /// - Parameters:
    ///     - type: an `ActivityProtocol` of activities.
    ///     - decoder: a custom decoder for the given activity type.
    ///     - subscription: a subscription block with changes.
    ///                     It will retrun a `Result` with `SubscriptionResponse` or `DecodingError`.
    ///
    /// - Returns: a `SubscribedChannel` keep the subscription util it will be deinit.
    ///            Store the object in a variable for the getting updates and then set it to nil to unsubscribe.
    
    public func subscribe(
        decoder: JSONDecoder = JSONDecoder.stream,
        subscription: @escaping SubscriptionResult
    ) -> SubscribedChannel {
        
        let channel = Channel(notificationChannelName, client: Client.fayeClient) { [weak self] data  in
            guard let self = self else {
                return
            }
            
            do {
                var response = try decoder.decode(LiveResponse.self, from: data)
                self.callbackQueue.async { subscription(.success(response)) }
                
            } catch let error as DecodingError {
                print("❌", #function, error)
                self.callbackQueue.async { subscription(.failure(.decoding(error))) }
                
            } catch {
                print("❌", #function, error)
                self.callbackQueue.async { subscription(.failure(.unexpected(error))) }
            }
        }
        
        channel.ext = ["api_key": Client.shared.apiKey, "signature": Client.shared.token, "user_id": notificationChannelName]
        
        do {
            try Client.fayeClient.subscribe(to: channel)
            
        } catch let error as Faye.Client.Error {
            if case .notConnected = error {
                Client.fayeClient.connect()
            } else {
                print("❌", #function, error)
                callbackQueue.async { subscription(.failure(.fayeClient(error))) }
            }
            
        } catch {
            print("❌", #function, error)
            callbackQueue.async { subscription(.failure(.unexpected(error))) }
        }
        
        return SubscribedChannel(channel)
    }
    
    /// A notification channel name.
    var notificationChannelName: ChannelName {
        return "site-\(Client.shared.appId)-feed-\(feedId.together)"
    }
}

// MARK: - Subscribed Channel

/// A subscribed channel holder.
public final class SubscribedChannel {
    private let channel: Channel
    
    public init(_ channel: Channel) {
        self.channel = channel
    }
    
    deinit {
        channel.unsubscribe()
    }
}

// MARK: - SubscriptionResponse
public struct LiveResponse: Codable {
    var deleted: [String]?
    var deletedForeignIDS: [[String]]?
    var feed: String?
    var new: [LiveData]?
    
    enum CodingKeys: String, CodingKey {
        case deleted
        case deletedForeignIDS = "deleted_foreign_ids"
        case feed, new
    }
}

// MARK: - New
public struct LiveData: Codable {
    var actor, foreignID: String?
    var hidden: Bool?
    var id, object, origin: String?
    var popularity: Int?
    var target, time, verb: String?
    
    enum CodingKeys: String, CodingKey {
        case actor
        case foreignID = "foreign_id"
        case hidden, id, object, origin, popularity, target, time, verb
    }
}
