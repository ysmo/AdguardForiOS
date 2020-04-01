/**
   This file is part of Adguard for iOS (https://github.com/AdguardTeam/AdguardForiOS).
   Copyright © Adguard Software Limited. All rights reserved.

   Adguard for iOS is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   Adguard for iOS is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with Adguard for iOS.  If not, see <http://www.gnu.org/licenses/>.
*/

import Foundation

protocol ChartViewModelProtocol {
    
    var requestsCount: Int { get set }
    var blockedCount: Int { get set }
    
    var blockedSavedKbytes: Int { get set }
    
    var chartDateType: ChartDateType { get set }
    var chartRequestType: ChartRequestType { get set }
    
    var chartPointsChangedDelegate: NumberOfRequestsChangedDelegate? { get set }
    
    func obtainStatistics()
}

protocol NumberOfRequestsChangedDelegate: class {
    func numberOfRequestsChanged()
}

enum ChartRequestType {
    case requests, blocked
}

class ChartViewModel: ChartViewModelProtocol {
    
    let chartView: ChartView?
    var chartPointsChangedDelegate: NumberOfRequestsChangedDelegate?
    
    var requestsCount: Int = 0
    var blockedCount: Int = 0
    
    var blockedSavedKbytes: Int = 0
        
    var requests: [RequestsStatisticsBlock] = []
    var blockedRequests: [RequestsStatisticsBlock] = []
    
    var chartDateType: ChartDateType = .alltime {
        didSet {
            changeChart()
        }
    }
    
    var chartRequestType: ChartRequestType = .requests {
        didSet {
            changeChart()
        }
    }
    
    private let dateFormatter = DateFormatter()
    
    private var timer: Timer?
    
    private let dnsStatisticsService: DnsStatisticsServiceProtocol
    
    // MARK: - init
    init(_ dnsStatisticsService: DnsStatisticsServiceProtocol, chartView: ChartView?) {
        self.dnsStatisticsService = dnsStatisticsService
        self.chartView = chartView
    }
    
    func obtainStatistics() {
        
        timer?.invalidate()
        timer = nil
        
        DispatchQueue(label: "obtainStatistics queue").async { [weak self] in
            guard let self = self else { return }
            let statistics = self.dnsStatisticsService.readStatistics()
            
            self.requests = statistics[.all] ?? []
            self.blockedRequests = statistics[.blocked] ?? []
            
            DispatchQueue.main.async {
                self.changeChart()
            }
            
            self.timer = Timer.scheduledTimer(withTimeInterval: self.dnsStatisticsService.minimumStatisticSaveTime, repeats: true, block: {[weak self] (timer) in
                self?.obtainStatistics()
            })
        }
    }
    
    // MARK: - private methods
    
    private func changeChart(){
    
        let requestsData = getPoints(from: requests)
        let blockedData = getPoints(from: blockedRequests)
        
        requestsCount = requestsData.number
        blockedCount = blockedData.number
        
        blockedSavedKbytes = blockedData.savedData
    
        chartView?.chartPoints = (requestsData.points, blockedData.points)
        chartPointsChangedDelegate?.numberOfRequestsChanged()
    }
    
    private func getPoints(from requests: [RequestsStatisticsBlock]) -> (points: [Point], number: Int, savedData: Int){
        let maximumPointsNumber = 50
        var pointsArray: [Point] = []
        var savedKbytes = 0
        var number = 0
                
        var requestsDates: [Date] = requests.map({ $0.date })
        requestsDates.sort(by: { $0 < $1 })
        
        let intervalTime = chartDateType.getTimeInterval(requestsDates: requestsDates)
        
        let firstDate = intervalTime.begin.timeIntervalSinceReferenceDate
        let lastDate = intervalTime.end.timeIntervalSinceReferenceDate
        
        chartView?.leftDateLabelText = chartDateType.getFormatterString(from: intervalTime.begin)
        chartView?.rightDateLabelText = chartDateType.getFormatterString(from: intervalTime.end)
        
        if requestsDates.count < 2 {
            return ([], 0, 0)
        }
        
        var xPosition: CGFloat = 0.0
        for request in requests {
            let date = request.date.timeIntervalSinceReferenceDate
            if (date > firstDate && date < lastDate) || chartDateType == .alltime {
                let point = Point(x: xPosition, y: CGFloat(integerLiteral: request.numberOfRequests))
                number += request.numberOfRequests
                savedKbytes += request.savedKbytes
                pointsArray.append(point)
                xPosition += 1.0
            }
        }
        
        if pointsArray.count > maximumPointsNumber {
            let points = rearrangePoints(from: pointsArray, max: maximumPointsNumber)
            return (points, number, savedKbytes)
        } else {
            return (pointsArray, number, savedKbytes)
        }
    }
    
    private func rearrangePoints(from points: [Point], max: Int) -> [Point] {
        var ratio: Float = Float(points.count) / Float(max)
        ratio = ceil(ratio)
        
        var copyPoints = points.map({$0.y})
        
        let intRatio = Int(ratio)
        var newPoints = [Point]()
        var xPosition: CGFloat = 0.0
        
        while !copyPoints.isEmpty {
            let points = copyPoints.prefix(intRatio)
            let sum = points.reduce(0, +)
            let point = Point(x: xPosition, y: sum)
            newPoints.append(point)
            
            xPosition += 1.0
            
            if copyPoints.count < intRatio {
                copyPoints.removeAll()
            } else {
                copyPoints.removeFirst(intRatio)
            }
        }
        
        return newPoints
    }
    
}
