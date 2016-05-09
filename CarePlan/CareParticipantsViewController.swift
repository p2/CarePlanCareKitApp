//
//  CareParticipantsViewController.swift
//  CarePlan
//
//  Created by Pascal Pfiffner on 07/05/16.
//  Copyright © 2016 CHIP. All rights reserved.
//

import CareKit
import C3PROCare


class CareParticipantsViewController: OCKConnectViewController, CareViewController {
	
	var planController: CarePlanController? {
		didSet {
			if let planController = planController {
				planController.planParticipants() { participants in
					self.contacts = participants
				}
			}
		}
	}
}

