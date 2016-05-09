//
//  CareOverviewViewController.swift
//  CarePlan
//
//  Created by Pascal Pfiffner on 06/05/16.
//  Copyright © 2016 CHIP. All rights reserved.
//

import UIKit
import C3PROCare
import SMART


class CareOverviewViewController: UIViewController, CareViewController {
	
	var planController: CarePlanController? {
		didSet {
			configureView()
		}
	}
	
	@IBOutlet var titleLabel: UILabel?
	@IBOutlet var subLabel: UILabel?
	
	
	// MARK: - View Tasks
	
	override func viewDidLoad() {
		super.viewDidLoad()
		configureView()
	}
	
	func configureView() {
		guard isViewLoaded() else {
			return
		}
		
		// resolve subject
		if let controller = planController {
			titleLabel?.text = "Loading..."
			controller.subjectOrGroup() { patient, group, reference in
				if let patient = patient {
					self.titleLabel?.text = HumanName.c3_humanName(patient.name) ?? "Unnamed Subject"
				}
				else if let group = group {
					self.titleLabel?.text = group.name
				}
				else {
					self.titleLabel?.text = reference?.display ?? "Unknown subject \(reference?.description ?? "nil")"
				}
			}
			subLabel?.text = "Care plan is \(controller.plan.status ?? "without status")"
		}
		else {
			titleLabel?.text = "No Care plan"
		}
	}
	
	@IBAction func refresh() {
		let app = UIApplication.sharedApplication().delegate as! AppDelegate
		app.loadCarePlan()
	}
}

