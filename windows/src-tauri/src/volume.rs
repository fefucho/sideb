//! Optional Windows low-volume range. The shared player's existing curve stays intact.
pub(crate) fn combined_gain(volume: f64, exponential: bool, track_gain: Option<f64>) -> Option<f64> {
    let base = track_gain.filter(|gain| gain.is_finite());
    if !exponential || volume <= 0.0 || !volume.is_finite() {
        return base;
    }
    let attenuation = -30.0 * (1.0 - volume.clamp(0.0, 100.0) / 100.0);
    if attenuation == 0.0 { base } else { Some(base.unwrap_or(0.0) + attenuation) }
}

#[cfg(test)]
mod tests {
    use super::combined_gain;
    #[test]
    fn optional_curve_preserves_endpoints_and_normalization() {
        assert_eq!(combined_gain(0.0, true, Some(-4.0)), Some(-4.0));
        assert_eq!(combined_gain(100.0, true, Some(-4.0)), Some(-4.0));
        assert_eq!(combined_gain(100.0, true, None), None);
        assert_eq!(combined_gain(25.0, false, Some(-4.0)), Some(-4.0));
        assert_eq!(combined_gain(25.0, true, Some(-4.0)), Some(-26.5));
        assert_eq!(combined_gain(25.0, true, None), Some(-22.5));
        assert_eq!(combined_gain(50.0, true, Some(f64::NAN)), Some(-15.0));
    }
    #[test]
    fn low_range_is_finite_monotonic_and_never_amplifies() {
        let mut previous = 0.0;
        for percent in 1..=100 {
            let db = combined_gain(percent as f64, true, None).unwrap_or(0.0);
            let amplitude = 10f64.powf(db / 20.0);
            assert!(amplitude.is_finite() && amplitude >= previous && amplitude <= 1.0);
            previous = amplitude;
        }
        assert!(combined_gain(1.0, true, None).unwrap() < -29.0);
    }
}
