import Foundation

// MARK: - Ninebot / Xiaomi error codes (v5.1)
//
// The code numbers and their short meanings are FACTS from the ScooterHacking wiki's
// "Ninebot ESx/Max Error Codes" and "Xiaomi error codes" pages (CC BY-SA 4.0) and Ninebot's
// ES protocol PDF appendix. All the wording below is HackTheScoot's own (nothing quoted),
// and the advice is general, unverified guidance. It never suggests firmware or serial-number
// changes. See ACKNOWLEDGEMENTS.md.

extension FaultCatalog {
    static let scooterCodeSource = "Code meanings: facts from the ScooterHacking wiki error-code pages (CC BY-SA 4.0) and Ninebot's ES protocol document. The wording and advice are HackTheScoot's own general guidance, unverified on your scooter. Experimental, untested on hardware."

    static let ninebot: [FaultInfo] = [
        FaultInfo(id: "NB 10", title: "10: Dashboard and controller aren't talking", meaning: "The dashboard (or Bluetooth board) can't reach the main controller.", whatToDo: "Turn it off. Check the cable between the dashboard and the controller in the stem. If it stays, it needs a repair shop.", severity: .stop),
        FaultInfo(id: "NB 11", title: "11: Motor phase A current out of range", meaning: "The controller measured an abnormal current on motor wire A.", whatToDo: "Stop riding. Check the motor cable and plug for damage. If it stays, get the motor and controller checked.", severity: .stop),
        FaultInfo(id: "NB 12", title: "12: Motor phase B current out of range", meaning: "The controller measured an abnormal current on motor wire B.", whatToDo: "Stop riding. Check the motor cable and plug for damage. If it stays, get the motor and controller checked.", severity: .stop),
        FaultInfo(id: "NB 13", title: "13: Motor phase C current out of range", meaning: "The controller measured an abnormal current on motor wire C.", whatToDo: "Stop riding. Check the motor cable and plug for damage. If it stays, get the motor and controller checked.", severity: .stop),
        FaultInfo(id: "NB 14", title: "14: Throttle out of range", meaning: "The throttle reads a position it shouldn't, often stuck, pressed at power-on, or unplugged.", whatToDo: "Let go of the throttle and restart. If it stays, check the throttle cable and plug.", severity: .stop),
        FaultInfo(id: "NB 15", title: "15: Brake lever out of range", meaning: "The brake lever sensor reads a position it shouldn't (stuck, faulty or unplugged).", whatToDo: "Don't ride until the brake works. Check the lever and its cable.", severity: .stop),
        FaultInfo(id: "NB 16", title: "16: Internal battery switch problem", meaning: "The circuit that switches the built-in battery isn't behaving.", whatToDo: "Stop riding and get the battery or controller checked.", severity: .stop),
        FaultInfo(id: "NB 17", title: "17: External battery switch problem", meaning: "The circuit that switches the extra (external) battery isn't behaving.", whatToDo: "Remove the extra battery and get it checked.", severity: .stop),
        FaultInfo(id: "NB 18", title: "18: Motor hall sensor problem", meaning: "The controller can't read the motor's position sensors.", whatToDo: "Turn it off. Check the small sensor plug between the motor and controller. If it stays, it needs a repair shop.", severity: .stop),
        FaultInfo(id: "NB 19", title: "19: Internal battery voltage out of range", meaning: "The built-in battery's voltage is too low or too high.", whatToDo: "Charge it with the original charger. If it stays, get the battery checked.", severity: .check),
        FaultInfo(id: "NB 20", title: "20: External battery voltage out of range", meaning: "The extra battery's voltage is too low or too high.", whatToDo: "Charge it. If it stays, get the extra battery checked.", severity: .check),
        FaultInfo(id: "NB 21", title: "21: Can't talk to the battery", meaning: "The controller gets no answer from the built-in battery's BMS.", whatToDo: "Check the battery's data plug. If it stays, the battery needs checking.", severity: .stop),
        FaultInfo(id: "NB 22", title: "22: Battery settings invalid", meaning: "The built-in battery's BMS reports a bad configuration.", whatToDo: "Get the battery checked by a repair shop.", severity: .check),
        FaultInfo(id: "NB 23", title: "23: Battery not activated", meaning: "The built-in battery reports a default (blank) identity, common after a battery swap.", whatToDo: "Get it checked by a repair shop.", severity: .check),
        FaultInfo(id: "NB 24", title: "24: Supply voltage out of range", meaning: "The voltage feeding the controller (or the charger) is wrong.", whatToDo: "Use the original charger. If it stays, get it checked.", severity: .check),
        FaultInfo(id: "NB 25", title: "25: Update communication failed", meaning: "A firmware update to the controller didn't finish talking.", whatToDo: "Turn the scooter fully off and on. Use only the official app for updates.", severity: .check),
        FaultInfo(id: "NB 26", title: "26: Controller memory save error", meaning: "The controller couldn't save its settings.", whatToDo: "Restart it. If it keeps coming back, the controller needs a repair shop.", severity: .check),
        FaultInfo(id: "NB 27", title: "27: Controller settings invalid", meaning: "The controller's stored settings don't match the board.", whatToDo: "Get it checked by a repair shop.", severity: .check),
        FaultInfo(id: "NB 28", title: "28: Motor driver short (high side)", meaning: "A power transistor in the controller looks shorted.", whatToDo: "Stop riding. This needs a repair shop.", severity: .stop),
        FaultInfo(id: "NB 29", title: "29: Motor driver short (low side)", meaning: "A power transistor in the controller looks shorted.", whatToDo: "Stop riding. This needs a repair shop.", severity: .stop),
        FaultInfo(id: "NB 31", title: "31: Program error", meaning: "The controller's program jumped somewhere it shouldn't.", whatToDo: "Restart it. If it keeps coming back, it needs a repair shop.", severity: .check),
        FaultInfo(id: "NB 32", title: "32: No IoT module", meaning: "Rental (shared) scooters need their tracking module. Retail scooters shouldn't show this.", whatToDo: "If this is a rental scooter, it belongs to the rental company.", severity: .info),
        FaultInfo(id: "NB 35", title: "35: Controller not activated", meaning: "The controller reports a default (blank) identity, common after a controller swap.", whatToDo: "Get it checked by a repair shop.", severity: .check),
        FaultInfo(id: "NB 36", title: "36: External battery plug or charge wire fault", meaning: "The plug for the extra battery or its charging wire has a problem.", whatToDo: "Check the plug and wire. Don't charge until it's checked.", severity: .stop),
        FaultInfo(id: "NB 37", title: "37: Charging socket or internal charge wire fault", meaning: "The charging socket or its wire to the built-in battery has a problem.", whatToDo: "Don't charge until it's checked.", severity: .stop),
        FaultInfo(id: "NB 38", title: "38: Charging over-current", meaning: "Too much current while charging, often the wrong charger.", whatToDo: "Unplug it. Use only the original charger.", severity: .stop),
        FaultInfo(id: "NB 39", title: "39: Internal battery too hot", meaning: "The built-in battery is overheating.", whatToDo: "Stop and let it cool somewhere safe, away from anything that can burn. Don't charge it hot.", severity: .stop),
        FaultInfo(id: "NB 40", title: "40: Controller too hot", meaning: "The controller is overheating.", whatToDo: "Stop and let it cool. Avoid long full-power climbs.", severity: .stop),
        FaultInfo(id: "NB 41", title: "41: External battery too hot", meaning: "The extra battery is overheating.", whatToDo: "Stop and let it cool somewhere safe. Don't charge it hot.", severity: .stop),
        FaultInfo(id: "NB 42", title: "42: Can't talk to the external battery", meaning: "No answer from the extra battery.", whatToDo: "Check its plug and that it's fastened properly.", severity: .check),
        FaultInfo(id: "NB 43", title: "43: External battery settings invalid", meaning: "The extra battery reports a bad configuration.", whatToDo: "Get it checked.", severity: .check),
        FaultInfo(id: "NB 44", title: "44: External battery not activated", meaning: "The extra battery reports a default (blank) identity.", whatToDo: "Get it checked.", severity: .check),
        FaultInfo(id: "NB 45", title: "45: Internal battery cell deeply discharged", meaning: "A cell in the built-in battery went too low.", whatToDo: "Don't ride. Charge with the original charger and get the battery checked.", severity: .stop),
        FaultInfo(id: "NB 46", title: "46: External battery cell deeply discharged", meaning: "A cell in the extra battery went too low.", whatToDo: "Don't use it. Get the battery checked.", severity: .stop),
        FaultInfo(id: "NB 47", title: "47: Internal battery protection board damaged", meaning: "The built-in battery's protection board reports damage.", whatToDo: "Stop using it. The battery needs replacing or repair.", severity: .stop),
        FaultInfo(id: "NB 48", title: "48: External battery protection board damaged", meaning: "The extra battery's protection board reports damage.", whatToDo: "Stop using it. Get it checked.", severity: .stop),
        FaultInfo(id: "NB 49", title: "49: Internal battery firmware mismatch", meaning: "The built-in battery's firmware doesn't match what the controller expects.", whatToDo: "Update with the official app, or get it checked.", severity: .check),
        FaultInfo(id: "NB 50", title: "50: External battery firmware mismatch", meaning: "The extra battery's firmware doesn't match.", whatToDo: "Update with the official app, or get it checked.", severity: .check),
        FaultInfo(id: "NB 51", title: "51: Bluetooth firmware doesn't match the controller", meaning: "The Bluetooth board and controller firmware versions don't fit together.", whatToDo: "Update with the official app, or get it checked.", severity: .check),
        FaultInfo(id: "NB 52", title: "52: Battery firmware doesn't match the controller", meaning: "The battery and controller firmware versions don't fit together (on rentals, the battery hatch lock).", whatToDo: "Update with the official app, or get it checked.", severity: .check),
        FaultInfo(id: "NB 54", title: "54: Motor phase error", meaning: "A problem on the motor wires (on rentals: the battery hatch lock link).", whatToDo: "Stop and check the motor wiring.", severity: .stop),
        FaultInfo(id: "NB 55", title: "55: Battery hatch unlocked", meaning: "Rental scooters: the battery hatch is open.", whatToDo: "Close the hatch.", severity: .info),
    ]

    static let xiaomi: [FaultInfo] = [
        FaultInfo(id: "MI 10", title: "10: Bluetooth board and controller aren't talking", meaning: "The Bluetooth/dashboard board can't reach the controller.", whatToDo: "Turn it off. Check the cable to the dashboard. If it stays, it needs a repair shop.", severity: .stop),
        FaultInfo(id: "MI 11", title: "11: Motor phase A current out of range", meaning: "The controller measured an abnormal current on motor wire A.", whatToDo: "Stop riding. Check the motor cable and plug for damage. If it stays, get the motor and controller checked.", severity: .stop),
        FaultInfo(id: "MI 12", title: "12: Motor phase B current out of range", meaning: "The controller measured an abnormal current on motor wire B.", whatToDo: "Stop riding. Check the motor cable and plug for damage. If it stays, get the motor and controller checked.", severity: .stop),
        FaultInfo(id: "MI 13", title: "13: Motor phase C current out of range", meaning: "The controller measured an abnormal current on motor wire C.", whatToDo: "Stop riding. Check the motor cable and plug for damage. If it stays, get the motor and controller checked.", severity: .stop),
        FaultInfo(id: "MI 14", title: "14: Throttle out of range", meaning: "The throttle reads a position it shouldn't, often stuck, pressed at power-on, or unplugged.", whatToDo: "Let go of the throttle and restart. If it stays, check the throttle cable and plug.", severity: .stop),
        FaultInfo(id: "MI 15", title: "15: Brake lever out of range", meaning: "The brake lever sensor reads a position it shouldn't (stuck, faulty or unplugged).", whatToDo: "Don't ride until the brake works. Check the lever and its cable.", severity: .stop),
        FaultInfo(id: "MI 18", title: "18: Motor sensor problem", meaning: "The controller can't read the motor's sensors.", whatToDo: "Turn it off and check the motor sensor plug. If it stays, it needs a repair shop.", severity: .stop),
        FaultInfo(id: "MI 21", title: "21: Can't talk to the battery", meaning: "The controller gets no answer from the built-in battery's BMS.", whatToDo: "Check the battery's data plug. If it stays, the battery needs checking.", severity: .stop),
        FaultInfo(id: "MI 22", title: "22: Battery settings invalid", meaning: "The built-in battery's BMS reports a bad configuration.", whatToDo: "Get the battery checked by a repair shop.", severity: .check),
        FaultInfo(id: "MI 23", title: "23: Battery not activated", meaning: "The built-in battery reports a default (blank) identity, common after a battery swap.", whatToDo: "Get it checked by a repair shop.", severity: .check),
        FaultInfo(id: "MI 24", title: "24: Charger voltage abnormal", meaning: "The charging voltage is wrong.", whatToDo: "Use only the original charger.", severity: .check),
        FaultInfo(id: "MI 26", title: "26: Controller memory save error", meaning: "The controller couldn't save its settings.", whatToDo: "Restart it. If it keeps coming back, the controller needs a repair shop.", severity: .check),
        FaultInfo(id: "MI 27", title: "27: Controller settings invalid", meaning: "The controller's stored settings don't match the board.", whatToDo: "Get it checked by a repair shop.", severity: .check),
        FaultInfo(id: "MI 28", title: "28: Power transistor problem", meaning: "A power transistor in the controller isn't behaving.", whatToDo: "Stop riding. It needs a repair shop.", severity: .stop),
        FaultInfo(id: "MI 29", title: "29: Power transistor problem (low side)", meaning: "A power transistor in the controller isn't behaving.", whatToDo: "Stop riding. It needs a repair shop.", severity: .stop),
        FaultInfo(id: "MI 35", title: "35: Controller not activated", meaning: "The controller reports a default (blank) identity, common after a controller swap.", whatToDo: "Get it checked by a repair shop.", severity: .check),
        FaultInfo(id: "MI 39", title: "39: Battery temperature abnormal", meaning: "The battery is too hot or too cold.", whatToDo: "Stop. Let it reach room temperature before riding or charging.", severity: .stop),
        FaultInfo(id: "MI 40", title: "40: Controller temperature abnormal", meaning: "The controller is too hot.", whatToDo: "Stop and let it cool.", severity: .stop),
    ]

    /// The explanation for an error number read from a Ninebot (register 0xB0) or Xiaomi.
    /// 0 = no error.
    static func explainCode(_ code: Int, xiaomi: Bool) -> FaultInfo? {
        guard code != 0 else { return nil }
        let list = xiaomi ? FaultCatalog.xiaomi : FaultCatalog.ninebot
        let prefix = xiaomi ? "MI" : "NB"
        if let f = list.first(where: { $0.id == "\(prefix) \(code)" }) { return f }
        return FaultInfo(id: "\(prefix) \(code)", title: "Error \(code)", meaning: "No explanation is known for this number yet.",
                         whatToDo: "If it stays on, stop and get the scooter checked. The official app may show its own message for it.", severity: .check)
    }
}
