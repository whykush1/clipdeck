import wave, struct, math

def generate_thock(filename, start_freq, end_freq, duration_ms):
    sample_rate = 44100
    num_samples = int(sample_rate * (duration_ms / 1000.0))
    
    wavef = wave.open(filename, 'w')
    wavef.setnchannels(1) # mono
    wavef.setsampwidth(2) 
    wavef.setframerate(sample_rate)
    
    for i in range(num_samples):
        t = float(i) / sample_rate
        # Exponential frequency sweep
        freq = start_freq * ((end_freq/start_freq) ** (t / (duration_ms/1000.0)))
        
        # Exponential volume envelope (fast decay)
        envelope = math.exp(-t * (1000.0 / (duration_ms * 0.3)))
        
        # Sine wave
        val = math.sin(2.0 * math.pi * freq * t) * envelope
        
        # Convert to 16-bit integer
        int_val = int(val * 32767.0 * 0.6) # 60% volume
        data = struct.pack('<h', int_val)
        wavef.writeframesraw(data)
        
    wavef.close()

generate_thock('app/Sources/CopySound.wav', 600, 150, 60)
generate_thock('app/Sources/PasteSound.wav', 800, 200, 60)
