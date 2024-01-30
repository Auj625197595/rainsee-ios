//
//  File.swift
//  
//
//  Created by jinjian on 2024/1/17.
//

import Foundation

class RequestUtil {
    static let shared = RequestUtil()
    
    private let baseURL = "https://api.yjllq.com/index.php/api/" // 替换成您的API主机地址
    
    private init() { }
    
    func createRequest(endpoint: String, method: String = "GET") -> URLRequest {
        guard let url = URL(string: baseURL + endpoint) else {
            fatalError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // 设置固定的请求头
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 添加语言信息到请求头
        request.setValue(languageHeaderValue(), forHTTPHeaderField: "Accept-Language")
        // 添加其他请求头（如果需要）
        // request.setValue("your-value", forHTTPHeaderField: "your-header-field")
        
        return request
    }
    
    private func languageHeaderValue() -> String {
        // 获取当前系统语言
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        return preferredLanguage
    }
}
