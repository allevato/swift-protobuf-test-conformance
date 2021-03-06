// ConformanceSources/main.swift - Conformance test main
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// -----------------------------------------------------------------------------
///
/// Google's conformance test is a C++ program that pipes data to/from another
/// process.  The tester sends data to the test wrapper which encodes and decodes
/// data according to the provided instructions.  This allows a single test
/// scaffold to exercise many differnt implementations.
///
// -----------------------------------------------------------------------------

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

import Foundation
import SwiftProtobuf

func readRequest() -> Data? {
    var rawCount: UInt32 = 0
    let read1 = fread(&rawCount, 1, 4, stdin)
    let count = Int(rawCount)
    if read1 < 4 {
        return nil
    }
    var buff = [UInt8](repeating: 0, count: count)
    let read2 = fread(&buff, 1, count, stdin)
    if read2 < count {
        return nil
    }
    return Data(bytes: buff)
}

func writeResponse(data: Data) {
    let bytes = [UInt8](data)
    var count = UInt32(bytes.count)
    fwrite(&count, 4, 1, stdout)
    _ = bytes.withUnsafeBufferPointer { bp in
        fwrite(bp.baseAddress, Int(count), 1, stdout)
    }
    fflush(stdout)
}

func buildResponse(protobuf: Data) -> Conformance_ConformanceResponse {
    var response = Conformance_ConformanceResponse()

    let request: Conformance_ConformanceRequest
    do {
        request = try Conformance_ConformanceRequest(protobuf: protobuf)
    } catch {
        response.runtimeError = "Failed to parse conformance request"
        return response
    }

    let parsed: Conformance_TestAllTypes?
    switch request.payload {
    case .protobufPayload(let data):
        do {
            parsed = try Conformance_TestAllTypes(protobuf: data)
        } catch let e {
            response.parseError = "Protobuf failed to parse: \(e)"
            return response
        }
    case .jsonPayload(let json):
        do {
            parsed = try Conformance_TestAllTypes(json: json)
        } catch let e {
            response.parseError = "JSON failed to parse: \(e)"
            return response
        }
    default:
        assert(false)
	return response
    }

    let testMessage: Conformance_TestAllTypes
    if let parsed = parsed {
        testMessage = parsed
    } else {
        response.parseError = "Failed to parse"
        return response
    }

    switch request.requestedOutputFormat {
    case .protobuf:
        do {
            response.protobufPayload = try testMessage.serializeProtobuf()
        } catch let e {
            response.serializeError = "Failed to serialize: \(e)"
        }
    case .json_:
        do {
            response.jsonPayload = try testMessage.serializeJSON()
        } catch let e {
            response.serializeError = "Failed to serialize: \(e)"
        }
    default:
        assert(false)
    }
    return response
}

func singleTest() throws -> Bool {
   if let indata = readRequest() {
       let response = buildResponse(protobuf: indata)
       let outdata = try response.serializeProtobuf()
       writeResponse(data: outdata)
       return true
   } else {
      return false
   }
}

Google_Protobuf_Any.register(messageType: Conformance_TestAllTypes.self)
while try singleTest() {
}

