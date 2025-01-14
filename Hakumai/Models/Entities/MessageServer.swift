//
//  MessageServer.swift
//  Hakumai
//
//  Created by Hiroyuki Onishi on 11/19/14.
//  Copyright (c) 2014 Hiroyuki Onishi. All rights reserved.
//

import Foundation

private let kRegExpPatternHostUser = "msg\\d+\\..+"
private let kRegExpPatternHostChannel = "omsg\\d+\\..+"

private let kMessageServersUser: [(serverNumber: Int, port: Int)] = [
    (101, 2805), (102, 2815), (103, 2825), (104, 2835), (105, 2845),
    (101, 2806), (102, 2816), (103, 2826), (104, 2836), (105, 2846),
    (101, 2807), (102, 2817), (103, 2827), (104, 2837), (105, 2847),
    (101, 2808), (102, 2818), (103, 2828), (104, 2838), (105, 2848),
    (101, 2809), (102, 2819), (103, 2829), (104, 2839), (105, 2849),
    (101, 2810), (102, 2820), (103, 2830), (104, 2840), (105, 2850),
    (101, 2811), (102, 2821), (103, 2831), (104, 2841), (105, 2851),
    (101, 2812), (102, 2822), (103, 2832), (104, 2842), (105, 2852),
    (101, 2813), (102, 2823), (103, 2833), (104, 2843), (105, 2853),
    (101, 2814), (102, 2824), (103, 2834), (104, 2844), (105, 2854),
]

private let kMessageServersChannel: [(serverNumber: Int, port: Int)] = [
    (101, 2815), (102, 2828), (103, 2841), (104, 2854), (105, 2867), (106, 2880),
    (101, 2816), (102, 2829), (103, 2842), (104, 2855), (105, 2868), (106, 2881),
    (101, 2817), (102, 2830), (103, 2843), (104, 2856), (105, 2869), (106, 2882),
]

class MessageServer: CustomStringConvertible {
    let roomPosition: RoomPosition
    let address: String
    let port: Int
    let thread: Int
    
    var isChannel: Bool {
        if address.hasRegexpPattern(kRegExpPatternHostChannel) {
            return true
        }
        
        // skip to examine kRegExpPatternHostUser, default live type is 'user'
        return false
    }
    
    var description: String {
        return (
            "MessageServer: roomPosition[\(roomPosition)] " +
            "address[\(address)] port[\(port)] thread[\(thread)]"
        )
    }
    
    // MARK: - Object Lifecycle
    init(roomPosition: RoomPosition, address: String, port: Int, thread: Int) {
        self.roomPosition = roomPosition
        self.address = address
        self.port = port
        self.thread = thread
    }

    // MARK: - Public Functions
    func previous() -> MessageServer? {
        return neighbor(direction: -1)
    }
    
    func next() -> MessageServer? {
        return neighbor(direction: 1)
    }
    
    func neighbor(direction direction: Int) -> MessageServer? {
        assert(direction == -1 || direction == 1)
        
        let roomPosition = RoomPosition(rawValue: self.roomPosition.rawValue + direction)
        var address = self.address
        let port = self.port
        let thread = self.thread + direction

        let serverNumber = MessageServer.extractServerNumber(address)
        
        if serverNumber == nil {
            return nil
        }
        
        let serverIndex = MessageServer.serverIndexWithChannel(isChannel, serverNumber: serverNumber!, port: port)
        
        if serverIndex == nil {
            return nil
        }
        
        var derived: (serverNumber: Int, port: Int)
        
        if direction == -1 && MessageServer.isFirstServerWithChannel(isChannel, serverNumber: serverNumber!, port: port) {
            derived = MessageServer.lastMessageServerWithChannel(isChannel)
        }
        else if direction == 1 && MessageServer.isLastServerWithChannel(isChannel, serverNumber: serverNumber!, port: port) {
            derived = MessageServer.firstMessageServerWithChannel(isChannel)
        }
        else {
            let index = serverIndex! + direction
            derived = isChannel ? kMessageServersChannel[index] : kMessageServersUser[index]
        }
        
        address = MessageServer.reconstructServerAddressWithBaseAddress(address, serverNumber: derived.serverNumber)

        return MessageServer(roomPosition: roomPosition!, address: address, port: derived.port, thread: thread)
    }
    
    // MARK: - Private Functions
    class func extractServerNumber(address: String) -> Int? {
        let regexp = "\\D+(\\d+).+"
        let serverNumber = address.extractRegexpPattern(regexp)
        
        return serverNumber == nil ? nil : Int(serverNumber!)
    }
    
    class func serverIndexWithChannel(isChannel: Bool, serverNumber: Int, port: Int) -> Int? {
        var index = 0
        
        for (n, p) in isChannel ? kMessageServersChannel : kMessageServersUser {
            if serverNumber == n && port == p {
                return index
            }
            
            index++
        }
        
        return nil
    }
    
    class func isFirstServerWithChannel(isChannel: Bool, serverNumber: Int, port: Int) -> Bool {
        let firstServer = MessageServer.firstMessageServerWithChannel(isChannel)
        let isFirst = (firstServer.serverNumber == serverNumber && firstServer.port == port)
        return isFirst
    }
    
    class func isLastServerWithChannel(isChannel: Bool, serverNumber: Int, port: Int) -> Bool {
        let lastServer = MessageServer.lastMessageServerWithChannel(isChannel)
        let isLast = (lastServer.serverNumber == serverNumber && lastServer.port == port)
        return isLast
    }
    
    class func firstMessageServerWithChannel(isChannel: Bool) -> (serverNumber: Int, port: Int) {
        let messageServers = isChannel ? kMessageServersChannel : kMessageServersUser
        return messageServers[0]
    }

    class func lastMessageServerWithChannel(isChannel: Bool) -> (serverNumber: Int, port: Int) {
        let messageServers = isChannel ? kMessageServersChannel : kMessageServersUser
        return messageServers[messageServers.count - 1]
    }
    
    class func reconstructServerAddressWithBaseAddress(baseAddress: String, serverNumber: Int) -> String {
        // split server address like followings, and reconstruct using given server number
        // - msg102.live.nicovideo.jp (user)
        // - omsg103.live.nicovideo.jp (channel)
        let regexp = try! NSRegularExpression(pattern: "(\\D+)\\d+(.+)", options: [])
        let matched = regexp.matchesInString(baseAddress, options: [], range: NSMakeRange(0, baseAddress.utf16.count))
        
        let hostPrefix = MessageServer.substringFromBaseString(baseAddress, nsRange: matched[0].rangeAtIndex(1))
        let domain = MessageServer.substringFromBaseString(baseAddress, nsRange: matched[0].rangeAtIndex(2))

        return hostPrefix + String(serverNumber) + domain
    }
    
    class func substringFromBaseString(base: String, nsRange: NSRange) -> String {
        let start = base.startIndex.advancedBy(nsRange.location)
        let end = base.startIndex.advancedBy(nsRange.location + nsRange.length)
        let range = Range<String.Index>(start: start, end: end)
        let substring = base.substringWithRange(range)
        
        return substring
    }
}

// this overload is used in test methods
func == (left: MessageServer, right: MessageServer) -> Bool {
    return (left.roomPosition == right.roomPosition &&
        left.address == right.address &&
        left.port == right.port &&
        left.thread == right.thread)
}

func != (left: MessageServer, right: MessageServer) -> Bool {
    return !(left == right)
}

func == (left: [MessageServer], right: [MessageServer]) -> Bool {
    if left.count != right.count {
        return false
    }
    
    for i in 0..<left.count {
        if left[i] != right[i] {
            return false
        }
    }
    
    return true
}
