// Simple animation state tracker with smooth interpolation
pub struct AnimState {
    pub start: std::time::Instant,
    pub duration: f32,
    pub reverse: bool,
    pub running: bool,
}

impl AnimState {
    pub fn new() -> Self {
        Self { start: std::time::Instant::now(), duration: 0.2, reverse: false, running: false }
    }

    pub fn start_forward(&mut self, duration: f32) {
        self.start = std::time::Instant::now();
        self.duration = duration;
        self.reverse = false;
        self.running = true;
    }

    pub fn start_reverse(&mut self, duration: f32) {
        self.start = std::time::Instant::now();
        self.duration = duration;
        self.reverse = true;
        self.running = true;
    }

    pub fn value(&self) -> f32 {
        if !self.running { return if self.reverse { 0.0 } else { 1.0 } }
        let elapsed = self.start.elapsed().as_secs_f32();
        let t = (elapsed / self.duration).clamp(0.0, 1.0);
        // M3 Standard easing approximation: smoothstep-like with slight overshoot
        let eased = t * t * (3.0 - 2.0 * t); // smoothstep
        if self.reverse { 1.0 - eased } else { eased }
    }

    #[allow(dead_code)]
    pub fn done(&self) -> bool {
        !self.running || self.start.elapsed().as_secs_f32() >= self.duration
    }
}
