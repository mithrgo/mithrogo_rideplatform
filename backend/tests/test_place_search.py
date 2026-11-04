"""Destination search is limited to the backend search radius, at the retrieval step."""

from core import place_search
from core.models import PlatformConfig
from tests.test_customer_extras import client_for

# Nizamabad centre, the rider's GPS position in these tests.
LAT, LNG = 18.6725, 78.0940


def _km_north(km):
    """A latitude that is `km` kilometres north of the rider (about 111 km per degree)."""
    return LAT + km / 111.0


def _item(osm_id, name, lat, lng, country="in"):
    return {
        "osm_type": "node",
        "osm_id": osm_id,
        "name": name,
        "display_name": f"{name}, Nizamabad, Telangana, India",
        "lat": str(lat),
        "lon": str(lng),
        "address": {"country_code": country, "city": "Nizamabad", "state": "Telangana"},
    }


def _stub_nominatim(monkeypatch, items):
    calls = []

    def fake_fetch(query, latitude, longitude, radius_km):
        calls.append((query, latitude, longitude, radius_km))
        return items

    monkeypatch.setattr(place_search, "_fetch", fake_fetch)
    return calls


def test_only_places_inside_the_configured_radius_are_returned(db, monkeypatch):
    _stub_nominatim(
        monkeypatch,
        [
            _item(1, "D Mart Nizamabad", _km_north(0.5), LNG),
            _item(2, "D Mart Armoor", _km_north(2.5), LNG),
            _item(3, "D Mart Hyderabad", 17.3850, 78.4867),  # about 130 km away
            _item(4, "D-Mart Raipur", 21.2514, 81.6296),  # about 460 km away
        ],
    )

    result = place_search.search_nearby("D Mart", LAT, LNG)

    assert result["radius_km"] == 3.0
    assert [place["name"] for place in result["results"]] == ["D Mart Nizamabad", "D Mart Armoor"]


def test_results_are_ordered_nearest_first(db, monkeypatch):
    _stub_nominatim(
        monkeypatch,
        [
            _item(1, "Far", _km_north(2.8), LNG),
            _item(2, "Near", _km_north(0.2), LNG),
            _item(3, "Middle", _km_north(1.4), LNG),
        ],
    )

    names = [place["name"] for place in place_search.search_nearby("mart", LAT, LNG)["results"]]

    assert names == ["Near", "Middle", "Far"]


def test_the_radius_comes_from_platform_config(db, monkeypatch):
    _stub_nominatim(monkeypatch, [_item(1, "Five km away", _km_north(5), LNG)])

    assert place_search.search_nearby("mart", LAT, LNG)["results"] == []

    config = PlatformConfig.load()
    config.search_radius_km = 10
    config.save()
    result = place_search.search_nearby("mart", LAT, LNG)

    assert result["radius_km"] == 10.0
    assert [place["name"] for place in result["results"]] == ["Five km away"]


def test_the_search_box_is_sent_to_nominatim_bounded_to_india(db, monkeypatch):
    calls = _stub_nominatim(monkeypatch, [])

    place_search.search_nearby("D Mart", LAT, LNG)

    assert calls == [("D Mart", LAT, LNG, 3.0)]


def test_repeated_searches_at_the_same_spot_reuse_the_answer(db, monkeypatch):
    calls = _stub_nominatim(monkeypatch, [_item(1, "D Mart", _km_north(0.5), LNG)])

    first = place_search.search_nearby("D Mart", LAT, LNG)
    second = place_search.search_nearby("d mart", LAT, LNG)

    assert first == second
    assert len(calls) == 1


def test_places_outside_india_are_dropped(db, monkeypatch):
    _stub_nominatim(monkeypatch, [_item(1, "Across the border", _km_north(0.5), LNG, country="np")])

    assert place_search.search_nearby("border", LAT, LNG)["results"] == []


def test_the_endpoint_returns_nearby_results_for_the_customer(db, monkeypatch, customer):
    _stub_nominatim(
        monkeypatch,
        [_item(1, "D Mart Nizamabad", _km_north(0.5), LNG), _item(2, "D Mart Raipur", 21.2514, 81.6296)],
    )

    response = client_for(customer).get(
        "/api/v1/customers/places/search/", {"q": "D Mart", "lat": LAT, "lng": LNG}
    )

    assert response.status_code == 200
    body = response.json()
    assert body["radius_km"] == 3.0
    assert [place["name"] for place in body["results"]] == ["D Mart Nizamabad"]
    assert set(body["results"][0]) >= {"id", "name", "address", "latitude", "longitude", "distance_km"}


def test_the_endpoint_says_so_when_nominatim_is_unreachable(db, monkeypatch, customer):
    def unreachable(*args):
        raise place_search.PlaceSearchUnavailable("timeout")

    monkeypatch.setattr(place_search, "_fetch", unreachable)

    response = client_for(customer).get("/api/v1/customers/places/search/", {"q": "D Mart", "lat": LAT, "lng": LNG})

    assert response.status_code == 503
    assert response.json()["code"] == "place_search_unavailable"


def test_short_queries_and_bad_coordinates_are_rejected(db, monkeypatch, customer):
    _stub_nominatim(monkeypatch, [])
    api = client_for(customer)

    assert api.get("/api/v1/customers/places/search/", {"q": "ab", "lat": LAT, "lng": LNG}).status_code == 400
    assert api.get("/api/v1/customers/places/search/", {"q": "mart", "lat": 99, "lng": LNG}).status_code == 400
    assert api.get("/api/v1/customers/places/search/", {"q": "mart"}).status_code == 400


def test_anonymous_users_cannot_search(db, api):
    response = api.get("/api/v1/customers/places/search/", {"q": "mart", "lat": LAT, "lng": LNG})

    assert response.status_code in (401, 403)
