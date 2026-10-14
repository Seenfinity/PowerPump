# AI food scanner (v1.1)

Taken out of the 1.0 app: it isn't reachable and its server isn't deployed.
To bring it back, move these files into the app target again
(ClaudeVisionService.swift → Core/Services, FoodScanModels.swift → Core/Models,
FoodScannerView.swift → Features/FoodScanner), restore `Config.scanProxyURL`
and `Config.weeklyScanLimit`, deploy CloudflareWorker/ and update the privacy
policy, which today says no third-party AI services are used.
