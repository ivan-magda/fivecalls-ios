// Copyright 5calls. All rights reserved. See LICENSE for details.

import XCTest
@testable import FiveCalls

final class FetchUserStatsOperationTests: XCTestCase {
    func testTransportErrorFinishesOperationAndReleasesQueue() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UserStatsFailureProtocol.self]
        let operation = FetchUserStatsOperation(config: config)
        let completed = expectation(description: "stats operation completed")
        let queueAdvanced = expectation(description: "next operation ran")
        operation.completionBlock = {
            XCTAssertTrue(operation.isFinished)
            XCTAssertFalse(operation.isExecuting)
            XCTAssertEqual((operation.error as? URLError)?.code, .notConnectedToInternet)
            completed.fulfill()
        }

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let nextOperation = BlockOperation { queueAdvanced.fulfill() }
        nextOperation.addDependency(operation)
        queue.addOperations([operation, nextOperation], waitUntilFinished: false)
        defer {
            // Release the queue if the lifecycle regression leaves this operation running.
            if !operation.isFinished {
                operation.finish()
            }
        }

        wait(for: [completed, queueAdvanced], timeout: 2)
    }

    func testSuccessfulResponseIsParsedBeforeCompletion() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UserStatsSuccessProtocol.self]
        let operation = FetchUserStatsOperation(config: config)
        let completed = expectation(description: "stats response parsed")
        operation.completionBlock = {
            XCTAssertTrue(operation.isFinished)
            XCTAssertFalse(operation.isExecuting)
            XCTAssertNil(operation.error)
            XCTAssertEqual(operation.httpResponse?.statusCode, 200)
            XCTAssertEqual(operation.userStats?.contact, 221)
            XCTAssertEqual(operation.userStats?.voicemail, 158)
            XCTAssertEqual(operation.userStats?.unavailable, 32)
            XCTAssertEqual(operation.userStats?.weeklyStreak, 10)
            XCTAssertEqual(operation.firstCallTime, Date(timeIntervalSince1970: 1487959763))
            completed.fulfill()
        }
        let queue = OperationQueue()
        queue.addOperation(operation)

        wait(for: [completed], timeout: 2)
    }
}

private final class UserStatsFailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

private final class UserStatsSuccessProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let data = Data("""
        {"stats":{"contact":221,"voicemail":158,"unavailable":32},"weeklyStreak":10,"firstCallTime":1487959763}
        """.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
