//
//  AppDelegate.swift
//  CarePlan
//
//  Created by Pascal Pfiffner on 06/05/16.
//  Copyright © 2016 CHIP. All rights reserved.
//

import UIKit
import C3PROCare
import SMART
import CareKit


protocol CareViewController: class {
	
	var planController: CarePlanController? { get set }
}


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, OCKCarePlanStoreDelegate {
	
	var window: UIWindow?
	
	/// The plan controller we use.
	var planController: CarePlanController? {
		didSet {
			
			// assign to our tab view controllers
			if let top = window?.rootViewController as? UITabBarController {
				top.viewControllers?.forEach() {
					if let tab = $0 as? CareViewController {
						tab.planController = planController
					}
					else if let navi = $0 as? UINavigationController, let top = navi.topViewController as? CareViewController {
						top.planController = planController
					}
				}
			}
			
			// add activities to the store (for now, error is usually "activity xy already exists", so we delete it and try to add again)
			if let planController = planController {
				planController.activities() { activities in
					guard let activities = activities else {
						return
					}
					for activity in activities {
						self.planStore.addActivity(activity) { success, error in
							if let error = error {
								NSLog("Error adding activity \(activity), trying to remove: \(error)")
								self.planStore.removeActivity(activity) { success, error in
									if success {
										NSLog("Okay, trying to add activity again")
										self.planStore.addActivity(activity) { success, error in
											if let error = error {
												NSLog("Still erroring adding activity \(activity): \(error)")
											}
										}
									}
									else {
										NSLog("Still erroring removing activity: \(activity): \(error)")
									}
								}
							}
						}
					}
				}
			}
		}
	}
	
	
	// MARK: - Care Plan
	
	lazy var planStore: OCKCarePlanStore = {
		let fm = NSFileManager.defaultManager()
		let url = fm.URLsForDirectory(NSSearchPathDirectory.CachesDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask).first!
		print("--->  Opening care plan store at \(url.absoluteString)")
		let store = OCKCarePlanStore(persistenceDirectoryURL: url)
		store.delegate = self
		return store
	}()
	
	func loadCarePlan() {
//		loadBundledCarePlan()
		loadRemoteCarePlan()
	}
	
	func loadBundledCarePlan() {
		do {
			let plan = try NSBundle.mainBundle().fhir_bundledResource("careplan-example-overweight") as! CarePlan
			planController = CarePlanController(plan: plan)
		}
		catch let error {
			NSLog("Error reading bundled CarePlan: \(error)")
		}
	}
	
	func loadRemoteCarePlan() {
		let server = Server(base: "http://nprogram.azurewebsites.net/")
//		server.logger = OAuth2DebugLogger(.Trace)
		
		CarePlan.read("1", server: server) { resource, error in
			if let error = error {
				NSLog("Error loading CarePlan: \(error)")
			}
			else if let plan = resource as? CarePlan {
				dispatch_async(dispatch_get_main_queue()) {
					self.planController = CarePlanController(plan: plan)
				}
			}
			else {
				NSLog("No error but unexpected resource instead of CarePlan received: \(resource)")
			}
		}
	}
	
	
	// MARK: - Delegate Methods
	
	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
		
		// care plan store
		if let top = window?.rootViewController as? UITabBarController {
			let cards = OCKCareCardViewController(carePlanStore: planStore)
			cards.title = "Activities"
			cards.tabBarItem = UITabBarItem(title: "Activities", image: UIImage(named: "carecard"), selectedImage: UIImage(named: "carecard-filled"))
			let navi = UINavigationController(rootViewController: cards)
			top.addChildViewController(navi)
		}
		else {
			fatalError("Window's root view controller must be a UITabBarController")
		}
		
		// load sample CarePlan
		loadCarePlan()
		
		return true
	}
	
	func carePlanStore(store: OCKCarePlanStore, didReceiveUpdateOfEvent event: OCKCarePlanEvent) {
		guard let planController = planController else {
			NSLog("I do not have a plan controller yet, cannot react to update to event \(event)")
			return
		}
		
		// TODO: Create task for any activity
		if let (activity, resource) = planController.activityWithId(event.activity.identifier) {
			guard .Completed == event.state else {
				NSLog("This activity has not been completed, not submitting task")
				return
			}
			
			// activity stands for a diagnostic order - send a Task
			if let order = resource as? DiagnosticOrder {
				submitTaskForOrder(order, forEvent: event, ofActivity: activity, inStore: store)
			}
			else {
				NSLog("I don't yet know how to handle activity \(activity) with resource \(resource)")
			}
		}
		else {
			NSLog("I know nothing of an activity with id \(event.activity.identifier)")
		}
	}
	
	
	// MARK: - Workflow Related Testing Methods
	
	func submitTaskForOrder(order: DiagnosticOrder, forEvent: OCKCarePlanEvent, ofActivity: CarePlanActivity, inStore store: OCKCarePlanStore) {
		order.subject?.resolve(Resource.self) { subject in
			guard let subject = subject else {
				NSLog("Task must have a subject, but the order's subject is empty")		// TODO: work this out
				return
			}
			
			let labServer = Server(base: "http://fhir3.healthintersections.com.au/open/")
//			labServer.logger = OAuth2DebugLogger(.Trace)
			
			// instantiate the task
			let task = Task(json: nil)
			task.created = DateTime.now()
			task.lastModified = DateTime.now()
			task.status = "requested"
			do {
				let lab = Organization(json: nil)
				lab._server = labServer
				lab.id = "ACME"
				lab.name = "ACME Labs Corp"
				
				task._server = labServer
				task.creator = try task.referenceResource(subject)
				task.for_fhir = try task.referenceResource(subject)
				task.subject = try task.referenceResource(order)
				task.owner = try task.containResource(lab, withDisplay: lab.name ?? "Lab Name")
			}
			catch let error {
				NSLog("Failed to contain creator: \(error)")
			}
			
			// create the task on the server
			NSLog("Creating task on \(labServer)...")
			task.create(labServer) { error in
				if let error = error {
					NSLog("Error submitting task \(task): \(error)")
				}
				else {
					NSLog("🤘🏼 Task submitted, id: \(task.id ?? "no id")\n\(task.asJSON())")
					let activity = self.createActivityForTask(task, inStore: store)
					self.pollOrder(order, representingActivity: activity, inStore: store)
				}
			}
		}
	}
	
	func createActivityForTask(task: Task, inStore store: OCKCarePlanStore) -> OCKCarePlanActivity {
		let components = NSCalendar.currentCalendar().componentsInTimeZone(NSTimeZone.localTimeZone(), fromDate: NSDate())
		let schedule = OCKCareSchedule.dailyScheduleWithStartDate(components, occurrencesPerDay: 1)
		let labName = task.owner?.resolved(Organization.self)?.name ?? task.owner?.display ?? "Unknown Lab Co."
		let activity = OCKCarePlanActivity.interventionWithIdentifier(
			task.id ?? "unidentified-task",
			groupIdentifier: nil,
			title: "Review Lab Results",
			text: labName,
			tintColor: nil,
			instructions: "Grab report from \(labName)",
			imageURL: nil,
			schedule: schedule,
			userInfo: nil)
		
		NSLog("Adding new activity for task \(task)")
		store.addActivity(activity) { success, error in
			if let error = error {
				NSLog("Failed to add activity for task \(task): \(error)")
			}
		}
		return activity
	}
	
	func pollOrder(order: DiagnosticOrder, representingActivity: OCKCarePlanActivity, inStore store: OCKCarePlanStore) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)) {
			var run = true
			while run {
				NSLog("Polling in 5...")
				sleep(5)
				NSLog("Polling status of task \(order)")
				
				let semaphore = dispatch_semaphore_create(0)
				DiagnosticOrder.read(order.id!, server: order._server!) { resource, error in
					guard let newOrder = resource as? DiagnosticOrder else {
						NSLog("Failed reading the order, received \(resource)")
						return
					}
					
					// order has been marked completed
					if "completed" == newOrder.status {
						run = false
						dispatch_sync(dispatch_get_main_queue()) {
							let alert = UIAlertController(title: "Task Complete!",
							                              message: "“\(representingActivity.title ?? "Activity")” has been completed 👍🏼",
							                              preferredStyle: .Alert)
							alert.addAction(UIAlertAction(title: "OK", style: .Cancel, handler: nil))
							self.window!.rootViewController?.presentViewController(alert, animated: true, completion: nil)
						}
					}
					else {
						NSLog("Order's status is “\(newOrder.status ?? "undefined")”, polling some more")
					}
					dispatch_semaphore_signal(semaphore)
				}
				dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
			}
		}
	}
}

