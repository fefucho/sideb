//! Automix: DJ-style transitions between two songs, rendered offline.
//!
//! [`prepare`] takes the end of one song and the whole of the next and returns
//! a file that plays the first one untouched for a while, transitions, and
//! then carries on with the second one untouched to its end. A player switches
//! to that file once, at a moment the first song is playing, and never has to
//! switch back.
//!
//! Everything works on stereo 44.1 kHz audio already decoded in memory; the
//! callers (the core, the lab bench) fetch and decode.

pub mod audio;
pub mod grid;
pub mod mix;
pub mod model;
pub mod prefetch;
pub mod stems;
pub mod stretch;
pub mod synth;
pub mod transition;

pub use mix::{Options, Refusal, StemMode, Track};
pub use transition::{prepare, Cancelled, Kind, Transition};
