import Testing
import Foundation
@testable import ChelkaCore

@Test func catalogStartsFromTheConfiguredCity() {
    let home = CityCatalog.all.first
    #expect(home?.name == Config.Weather.cityName)
    #expect(home?.latitude == Config.Weather.latitude)
    #expect(home?.longitude == Config.Weather.longitude)
}

@Test func everyCityIsOnEarthAndNamed() {
    for city in CityCatalog.all {
        #expect(!city.name.isEmpty)
        #expect(Config.Limits.latitude.contains(city.latitude))
        #expect(Config.Limits.longitude.contains(city.longitude))
    }
}

/// Поле поиска — вместо ввода чисел, поэтому искать надо так, как человек
/// печатает: без учёта регистра и не заботясь о точных буквах вроде «ё».
@Test func searchIgnoresCaseAndDiacritics() {
    #expect(CityCatalog.search("астана").first?.name == "Астана")
    #expect(CityCatalog.search("АЛМА").first?.name == "Алматы")
    // «Кельн» без точек над «ё» обязан находить «Кёльн»: на клавиатуре «ё»
    // стоит в стороне, и никто её не набирает.
    #expect(CityCatalog.search("Кельн").first?.name == "Кёльн")
}

@Test func emptySearchOffersEverything() {
    #expect(CityCatalog.search("").count == CityCatalog.all.count)
    #expect(CityCatalog.search("   ").count == CityCatalog.all.count)
}

@Test func searchWithoutMatchesFindsNothing() {
    #expect(CityCatalog.search("зурбаган").isEmpty)
}

/// Выбор города — это подстановка координат, а не отдельная сущность в
/// настройках: иначе город и координаты могли бы разойтись.
@Test func choosingCityFillsCoordinatesAndName() {
    guard let almaty = CityCatalog.search("Алматы").first else {
        #expect(Bool(false), "Алматы нет в списке")
        return
    }
    let moved = Settings.defaults.choosing(almaty)
    #expect(moved.weatherCity == almaty.name)
    #expect(moved.weatherLatitude == almaty.latitude)
    #expect(moved.weatherLongitude == almaty.longitude)
    // Остальное не тронуто.
    #expect(moved.batteryLow == Settings.defaults.batteryLow)
}

/// Координаты, введённые руками, стирают название города: «Астана» с
/// координатами другого места — вранье в интерфейсе.
@Test func manualCoordinateDropsTheCityName() {
    let moved = Settings.defaults.settingLatitude(43.2)
    #expect(moved.weatherCity.isEmpty)
    #expect(moved.weatherLatitude == 43.2)
    #expect(moved.weatherLongitude == Settings.defaults.weatherLongitude)

    let movedEast = Settings.defaults.settingLongitude(76.9)
    #expect(movedEast.weatherCity.isEmpty)
    #expect(movedEast.weatherLongitude == 76.9)

    // Тот же самый ввод города не стирает: человек только что его выбрал.
    let unchanged = Settings.defaults.settingLatitude(Settings.defaults.weatherLatitude)
    #expect(unchanged.weatherCity == Settings.defaults.weatherCity)
}
