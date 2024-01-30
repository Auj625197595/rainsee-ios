// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import CoreData
import Foundation
import os.log
import Shared
import WebKit

@objc(Userscript)
public final class Userscript: NSManagedObject, CRUD, Encodable {
    enum CodingKeys: String, CodingKey {
        case name
        case desc
        case script
        case uuid
        case version
        case createtime
        case run_at
        case hosts
        case enable
        case cid
        case origin_url
        // 添加其他属性...
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(desc, forKey: .desc)
        try container.encode(script, forKey: .script)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(version, forKey: .version)
        try container.encode(createtime, forKey: .createtime)
        try container.encode(run_at, forKey: .run_at)
        try container.encode(hosts, forKey: .hosts)
        try container.encode(enable, forKey: .enable)
        try container.encode(cid, forKey: .cid)
        try container.encode(origin_url, forKey: .origin_url)
        // 添加其他属性...

        // 这里可以继续编码其他属性
    }

    @NSManaged public var uuid: String?

    @NSManaged public var createtime: Int32
    @NSManaged public var desc: String?
    @NSManaged public var hosts: String
    @NSManaged public var name: String?
    @NSManaged public var run_at: Int16
    @NSManaged public var script: String?
    @NSManaged public var version: String?

    @NSManaged public var enable: Bool

    @NSManaged public var cid: Int64
    @NSManaged public var origin_url: String?

    public var id: String {
        uuid ?? UUID().uuidString
    }

    public static func add(name: String, desc: String, script: String, version: String, cid: Int64, origin_url: String, completion: ((_ uuid: String) -> Void)? = nil) {
        DataController.perform(context: .new(inMemory: false), save: false) { context in
            var folderId: String = UUID().uuidString

            let userscript = Userscript(context: context)
            userscript.name = name
            userscript.desc = desc
            userscript.script = script
            userscript.uuid = folderId
            userscript.cid = cid
            userscript.origin_url = origin_url
            userscript.version = version
            userscript.createtime = Int32(Date().timeIntervalSince1970)
            userscript.run_at = 0
            userscript.hosts = ""
            userscript.enable = true

            Userscript.saveContext(context)

            DispatchQueue.main.async {
                completion?(folderId)
            }
        }
    }

    // 通过 UUID 查找 Userscript 对象的方法
    public class func findByUUID(_ uuid: String, context: NSManagedObjectContext? = nil) -> Userscript? {
        let contextToUse = context ?? DataController.viewContext
        let fetchRequest: NSFetchRequest<Userscript> = Userscript.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "uuid == %@", uuid)

        do {
            let results = try contextToUse.fetch(fetchRequest)
            return results.first
        } catch {
            print("Error fetching Userscript by UUID: \(error)")
            return nil
        }
    }

    public static func getAll(context: NSManagedObjectContext? = nil) -> [Userscript] {
        Userscript.all(where: NSPredicate(format: "createtime > 0"), context: context ?? DataController.viewContext) ?? []
    }
    public static func getEnable(context: NSManagedObjectContext? = nil) -> [Userscript] {
        Userscript.all(where: NSPredicate(format: "enable = true"), context: context ?? DataController.viewContext) ?? []
    }
    public static func remove(_ uuid: String, completion: (() -> Void)? = nil) {
        Userscript.deleteAll(
            predicate: NSPredicate(format: "uuid == %@", uuid),
            includesPropertyValues: false,
            completion: completion)
    }

    public static func updateFolder(folderID: NSManagedObjectID, _ update: @escaping (Result<Userscript, Error>) -> Void) {
        DataController.perform(context: .new(inMemory: false), save: true) { context in
            do {
                guard let folder = try context.existingObject(with: folderID) as? Userscript else {
                    fatalError("folder ID \(folderID) is not a Userscript")
                }

                update(.success(folder))
            } catch {
                update(.failure(error))
            }
        }
    }

    @nonobjc
    private class func fetchRequest() -> NSFetchRequest<Userscript> {
        NSFetchRequest<Userscript>(entityName: "Userscript")
    }

    private static func entity(_ context: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: "Userscript", in: context)!
    }

    private static func saveContext(_ context: NSManagedObjectContext) {
        if context.concurrencyType == .mainQueueConcurrencyType {
            Logger.module.warning("Writing to view context, this should be avoided.")
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                assertionFailure("Error saving DB: \(error.localizedDescription)")
            }
        }
    }

    public func update(with userInfo: [String: Any],
                       context: WriteContext = .new(inMemory: false))
    {
        DataController.perform(context: context) { context in
            guard let userscript = context.object(with: self.objectID) as? Userscript else { return }

            do {
                // 检查是否包含需要更新的属性
                if let name = userInfo["name"] as? String {
                    userscript.name = name
                }

                print("Received message body: \(userInfo)")
                if let enable = userInfo["enable"] as? Bool {
                    userscript.enable = enable
                }

                if let script = userInfo["script"] as? String {
                    userscript.script = script
                }

                if let origin_url = userInfo["origin_url"] as? String {
                    userscript.origin_url = origin_url
                }

                // 添加其他需要更新的属性...

                // 保存上下文以使更改生效
                // Userscript.saveContext(context)

            } catch {}
        }
      
    }
}
