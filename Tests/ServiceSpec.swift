//
//  ServiceTests.swift
//  ServiceTests
//
//  Created by Paul on 2015/6/14.
//  Copyright © 2015 Bust Out Solutions. All rights reserved.
//

import Siesta
import Quick
import Nimble

class ServiceSpec: QuickSpec
    {
    override func spec()
        {
        let service  = specVar { Service(base: "https://zingle.frotz") }
        
        describe("init()")
            {
            it("enforces a trailing slash on baseURL")
                {
                expect("http://foo.bar")     .to(expandToBaseURL("http://foo.bar/"))
                expect("http://foo.bar/")    .to(expandToBaseURL("http://foo.bar/"))
                expect("http://foo.bar/baz") .to(expandToBaseURL("http://foo.bar/baz/"))
                expect("http://foo.bar/baz/").to(expandToBaseURL("http://foo.bar/baz/"))
                }
                
            it("preserves baseURL query parameters")
                {
                expect("http://foo.bar?you=mysunshine")     .to(expandToBaseURL("http://foo.bar/?you=mysunshine"))
                expect("http://foo.bar/?you=mysunshine")    .to(expandToBaseURL("http://foo.bar/?you=mysunshine"))
                expect("http://foo.bar/baz?you=mysunshine") .to(expandToBaseURL("http://foo.bar/baz/?you=mysunshine"))
                expect("http://foo.bar/baz/?you=mysunshine").to(expandToBaseURL("http://foo.bar/baz/?you=mysunshine"))
                }
            }
        
        describe("resource()")
            {
            it("returns a resource that belongs to this service")
                {
                expect(service().resource("/foo").service)
                    .to(equal(service()))
                }
            
            it("resolves all paths as subpaths of baseURL")
                {
                // Note that checkPathExpansion tests both with & without leading slash
                checkPathExpansion("https://foo.bar",    path:"",         expect:"https://foo.bar/")
                checkPathExpansion("https://foo.bar",    path:"baz",      expect:"https://foo.bar/baz")
                checkPathExpansion("https://foo.bar",    path:"baz/fez",  expect:"https://foo.bar/baz/fez")
                checkPathExpansion("https://foo.bar",    path:"baz/fez/", expect:"https://foo.bar/baz/fez/")
                checkPathExpansion("https://foo.bar/v1", path:"baz",      expect:"https://foo.bar/v1/baz")
                checkPathExpansion("https://foo.bar/v1", path:"baz/fez",  expect:"https://foo.bar/v1/baz/fez")
                // TODO: Should there be special handling for paths starting with "." and ".."?
                }

            it("preserves baseURL query params")
                {
                checkPathExpansion("https://foo.bar/?a=b&x=y",   path:"baz/fez/", expect:"https://foo.bar/baz/fez/?a=b&x=y")
                checkPathExpansion("https://foo.bar/v1?a=b&x=y", path:"baz",      expect:"https://foo.bar/v1/baz?a=b&x=y")
                }
            }
        
        describe("caching")
            {
            it("gives the same Resource instance for the same path")
                {
                expect(service().resource("/foo"))
                    .to(beIdenticalTo(service().resource("/foo")))
                }
            
            it("gives the same Resource instance no matter how it’s constructed")
                {
                expect(service().resource("/foo").child("oogle").child("baz").relative("../bar"))
                    .to(beIdenticalTo(service().resource("/foo/bar")))
                }
            }
        
        describe("configuration")
            {
            let resource0 = specVar { service().resource("/foo") },
                resource1 = specVar { service().resource("/bar") }
            
            it("applies global config to all resources")
                {
                service().configureResources { $0.config.expirationTime = 17 }
                expect(resource0().config.expirationTime).to(equal(17))
                expect(resource1().config.expirationTime).to(equal(17))
                }

            it("passes through the default configuration")
                {
                service().configureResources { $0.config.retryTime = 17 }
                expect(resource0().config.expirationTime).to(equal(30))
                }

            it("applies predicate config only to matching resources")
                {
                service().configureResources("foo", predicate: { $0.absoluteString.hasSuffix("foo") })
                    { $0.config.expirationTime = 17 }
                expect(resource0().config.expirationTime).to(equal(17))
                expect(resource1().config.expirationTime).to(equal(30))
                }
            
            context("using wilcards")
                {
                func checkPattern(pattern: String, matches: Bool, _ path: String, params: [String:String] = [:])
                    {
                    let service = Service(base: "https://foo.bar/v1")
                    service.configureResources(pattern) { $0.config.expirationTime = 6 }
                    
                    var resource = service.resource(path)
                    for (k,v) in params
                        { resource = resource.withParam(k, v) }
                    
                    let actual = resource.config.expirationTime,
                        expected = matches ? 6.0 : 30.0,
                        matchword = matches ? "to" : "not to"
                    XCTAssert(expected == actual, "Expected \(pattern) \(matchword) match \(path)")
                    }
                
                it("matches against the base URL")
                    {
                    checkPattern("fez",  matches: true,  "https://foo.bar/v1/fez")
                    checkPattern("/fez", matches: true,  "https://foo.bar/v1/fez")
                    checkPattern("/fez", matches: false, "https://foo.com/v1/fez")
                    }
                
                it("matches full URLs")
                    {
                    checkPattern("https://foo.com/*/fez", matches: false, "https://foo.bar/v1/fez")
                    checkPattern("https://foo.com/*/fez", matches: true,  "https://foo.com/v1/fez")
                    }
                
                it("ignores a leading slash")
                    {
                    checkPattern("hither/thither", matches: true, "/hither/thither")
                    checkPattern("/hither/thither", matches: true, "hither/thither")
                    }
                
                it("matches path segments with *")
                    {
                    checkPattern("/*",     matches: true,  "/hither")
                    checkPattern("/*",     matches: false, "/hither/")
                    checkPattern("/*",     matches: false, "/hither/thither")
                    checkPattern("/*/b",   matches: false, "/a/")
                    checkPattern("/*/b",   matches: true,  "/a/b")
                    checkPattern("/*/b",   matches: false, "/a/b/")
                    checkPattern("/a/*/c", matches: true,  "/a/blarg/c")
                    checkPattern("/a/*/c", matches: false, "/a/c")
                    checkPattern("/*x*/c", matches: true,  "/x/c")
                    checkPattern("/*x*/c", matches: true,  "/foxy/c")
                    checkPattern("/*x*/c", matches: false, "/fozzy/c")
                    }
                
                it("matches across segments with **")
                    {
                    checkPattern("/**",     matches: true,  "/")
                    checkPattern("/**",     matches: true,  "/hither")
                    checkPattern("/**",     matches: true,  "/hither/thither/yon")
                    checkPattern("/a/**/b", matches: true,  "/a/b")
                    checkPattern("/a/**/b", matches: true,  "/a/1/2/3/b")
                    checkPattern("/a/**/b", matches: false, "/a1/2/3/b")
                    checkPattern("/a/**/b", matches: false, "/a/1/2/3b")
                    checkPattern("/**x**",  matches: true,  "/how/many/tests/exactly/do/we/need")
                    checkPattern("/**x**",  matches: false, "/just/a/health/handful")
                    checkPattern("/**/*",   matches: true,  "/a/b")
                    checkPattern("/**/*",   matches: true,  "/ab")
                    }

                it("ignores query strings in the matched URL")
                    {
                    checkPattern("/*/b",  matches: true, "/a/b", params: ["foo": "bar"])
                    checkPattern("/**/b", matches: true, "/a/b", params: ["foo": "bar"])
                    }
                }
            }
        }
    }


// MARK: - Custom matchers

func expandToBaseURL(expectedURL: String) -> MatcherFunc<String>
    {
    return MatcherFunc
        {
        actual, failureMessage in

        let base = try! actual.evaluate() ?? "",
            service = Service(base: base),
            actualURL = service.baseURL?.absoluteString
        failureMessage.stringValue =
            "expected baseURL \(base.debugDescription)"
            + " to expand to \(expectedURL.debugDescription),"
            + " but got \(actualURL.debugDescription)"
        return actualURL == expectedURL
        }
    }

func expandToResourceURL(expectedURL: String) -> MatcherFunc<(String,String)>
    {
    return MatcherFunc
        {
        inputs, failureMessage in
        
        let (base, resourcePath) = try! inputs.evaluate()!,
            service = Service(base: base),
            resource = service.resource(resourcePath),
            actualURL = resource.url?.absoluteString
        failureMessage.stringValue =
            "expected base \(base.debugDescription)"
            + " and resource path \(resourcePath.debugDescription)"
            + " to expand to \(expectedURL.debugDescription),"
            + " but got \(actualURL.debugDescription)"
        return actualURL == expectedURL
        }
    }

/// Checks resourcePath with and without a leading slash.
///
func checkPathExpansion(base: String, path resourcePath: String, expect expectedExpansion: String)
    {
    for resourcePathVariant in [resourcePath, "/" + resourcePath]
        {
        expect((base, resourcePathVariant))
            .to(expandToResourceURL(expectedExpansion))
        }
    }