// Shapes returned by /api/v1/admin/ (apps/backoffice/serializers.py).

export type UserBrief = { id: string; phone: string; name: string; role: string; is_active: boolean };

export type DayRow = {
  date: string; rides_requested: number; rides_completed: number; rides_cancelled: number; bike_rides: number;
  auto_rides: number; gross_fares: string; discounts: string; platform_share: string; subscription_revenue: string;
  ride_payments: string; dues_collected: string; wallet_top_ups: string; fee_revenue: string;
};

export type Ride = {
  id: string; status: string; vehicle_type: string; customer: UserBrief; captain_id: number | null;
  captain_name: string | null; captain_phone: string | null; pickup_address: string; pickup_latitude: string;
  pickup_longitude: string; drop_address: string; drop_latitude: string; drop_longitude: string;
  estimated_distance_km: string; estimated_fare: string; final_fare: string | null; discount_amount: string;
  payable_fare: string; promo_code: string; payment_method: string; payment_status: string; cancelled_by: string;
  cancellation_reason: string; cancellation_fee: string; cancellation_fee_status: string; is_platform_ride: boolean;
  requested_at: string; accepted_at: string | null; arrived_at: string | null; started_at: string | null;
  completed_at: string | null; cancelled_at: string | null;
  captain_location?: { latitude: string; longitude: string; updated_at: string | null } | null;
};

export type RideDetail = Ride & {
  estimated_duration_minutes: number; cancellation_note: string; start_pin_attempts: number;
  share_reason: string | null; platform_share_amount: string | null;
  events: { id: number; from_status: string; to_status: string; actor: UserBrief | null; note: string; created_at: string }[];
  offers: { id: number; sequence: number; captain_id: number; captain_phone: string; distance_km: string;
    status: string; expires_at: string; responded_at: string | null }[];
  rating: { rating: number; comment: string } | null;
};

export type Vehicle = { id: number; vehicle_type: string; registration_number: string; make: string; model: string;
  color: string; is_verified: boolean; verified_at: string | null };

export type Captain = {
  id: number; user: UserBrief; kyc_status: string; kyc_rejection_reason: string; online_status: string;
  rating: string; total_rides: number; cancelled_rides: number; license_number: string;
  license_expiry: string | null; day_vehicle_type: string | null; current_latitude: string | null;
  current_longitude: string | null; last_location_at: string | null; created_at: string;
};

export type CaptainDetail = Captain & {
  date_of_birth: string | null; address: string; vehicles: Vehicle[];
  documents: { id: number; doc_type: string; file_url: string; created_at: string }[];
};

export type Customer = {
  id: string; phone: string; name: string; email: string | null; is_active: boolean; deleted_at: string | null;
  total_rides: number; completed_rides: number; emergency_contact_name: string; emergency_contact_phone: string;
  referral_code: string | null; created_at: string;
};

export type Ticket = { id: number; user: UserBrief; category: string; ride_id: string | null; description: string;
  status: string; resolution_note: string; is_sos: boolean; created_at: string; updated_at: string };

export type TicketDetail = Ticket & {
  messages: { id: number; is_staff: boolean; author: UserBrief | null; body: string; created_at: string }[];
};

export type Sos = { id: number; user: UserBrief; ride_id: string | null; ride_status: string | null;
  ticket_id: number | null; latitude: string | null; longitude: string | null; note: string; status: string;
  handled_by: UserBrief | null; acknowledged_at: string | null; resolved_at: string | null; resolution_note: string;
  created_at: string };

export type Payment = { id: string; user: UserBrief; payment_type: string; amount: string; currency: string;
  provider: string; provider_order_id: string; provider_payment_id: string | null; status: string;
  metadata: Record<string, unknown>; created_at: string; updated_at: string };

export type Subscription = { id: number; captain_id: number; captain_phone: string; plan_code: string;
  plan_name: string; amount: string; status: string; start_at: string | null; expires_at: string | null;
  penalty_pending: boolean; created_at: string };

export type Due = { id: number; captain_id: number; captain_phone: string; ride_id: string | null; due_type: string;
  amount: string; status: string; created_at: string; settled_at: string | null };

export type Promo = { id: number; code: string; description: string; discount_type: "FLAT" | "PERCENT";
  value: string; max_discount: string | null; min_fare: string; valid_from: string | null;
  valid_until: string | null; max_uses_total: number | null; max_uses_per_user: number; first_ride_only: boolean;
  is_active: boolean; times_used: number; created_at: string };

export type Fare = { id: number; vehicle_type: string; base_fare: string; per_km: string; minimum_fare: string;
  platform_customer_fee: string; is_active: boolean; updated_at: string };

export type Plan = { id: number; code: string; name: string; plan_type: string; amount: string;
  duration_hours: number | null; vehicle_type: string | null; qualifying_rides: number | null;
  shortfall_fee: string | null; is_active: boolean; updated_at: string };

export type AuditEntry = { id: number; actor: UserBrief | null; action: string; model: string; object_id: string;
  changes: Record<string, unknown>; created_at: string };

export type QuickPlace = { id: number; name: string; address: string; latitude: string; longitude: string;
  icon: string; sort_order: number; is_active: boolean; updated_at: string };
