// Shared: Log

// Renders ClickSoundEffects WAVs from cuelume's "select" cue (https://cuelume-site.pages.dev, MIT, Daniel Belyi).

import Foundation

enum Configuration {
  static let sampleRate = 44_100.0
  static let renderDuration = 0.32
  static let stopPadding = 0.05
  static let randomSeed: UInt64 = 0xC0E1_0000
  static let leftPitch = 0.95
  static let rightPitch = 1.05
  static let defaultUpPitch = 1.03
  static let defaultUpGapMilliseconds = 110.0
  static let defaultGainDecibels = 14.0
}

extension Data {
  mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
    var littleEndianValue = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
  }
}

enum FilterType {
  case bandpass
  case lowpass
}

enum Layer {
  case tone(frequency: Glide, envelope: Envelope)
  case noise(filterType: FilterType, frequency: Double, q: Double, envelope: Envelope)
}

struct Envelope {
  let attack: Double
  let decay: Double
  let peak: Double

  var stopTime: Double { attack + decay + Configuration.stopPadding }

  func value(at time: Double) -> Double {
    if time < 0 || time >= stopTime {
      return 0
    }

    if time < attack {
      return peak * time / attack
    }

    if time < attack + decay {
      return peak * pow(1e-4 / peak, (time - attack) / decay)
    }

    return 1e-4
  }
}

struct Glide {
  let from: Double
  let to: Double
  let duration: Double

  func value(at time: Double) -> Double {
    guard time < duration else {
      return to
    }

    return from * pow(to / from, time / duration)
  }
}

struct Biquad {
  private var b0 = 0.0
  private var b1 = 0.0
  private var b2 = 0.0
  private var a1 = 0.0
  private var a2 = 0.0
  private var x1 = 0.0
  private var x2 = 0.0
  private var y1 = 0.0
  private var y2 = 0.0

  init(type: FilterType, frequency: Double, q: Double) {
    let w0 = 2 * Double.pi * frequency / Configuration.sampleRate
    let cosW0 = cos(w0)

    switch type {
    case .bandpass:
      let alpha = sin(w0) / (2 * q)
      let a0 = 1 + alpha

      self.b0 = alpha / a0
      self.b1 = 0
      self.b2 = -alpha / a0
      self.a1 = -2 * cosW0 / a0
      self.a2 = (1 - alpha) / a0

    case .lowpass:
      let alpha = sin(w0) / (2 * pow(10, q / 20))
      let a0 = 1 + alpha

      self.b0 = (1 - cosW0) / 2 / a0
      self.b1 = (1 - cosW0) / a0
      self.b2 = (1 - cosW0) / 2 / a0
      self.a1 = -2 * cosW0 / a0
      self.a2 = (1 - alpha) / a0
    }
  }

  mutating func process(_ input: Double) -> Double {
    let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2

    self.x2 = x1
    self.x1 = input
    self.y2 = y1
    self.y1 = output

    return output
  }
}

struct StereoSignal {
  var left: [Double]
  var right: [Double]
}

struct SplitMix64: RandomNumberGenerator {
  var state: UInt64

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15

    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB

    return value ^ (value >> 31)
  }
}

struct Modifiers {
  var pitch = 1.0
  var level = 1.0
  var length = 1.0
  var brightness = 1.0

  var clampedPitch: Double { min(1.25, max(0.75, pitch)) }
  var clampedLength: Double { min(1.6, max(0.6, length)) }

  static func repeatSoftening(gapMilliseconds: Double) -> Modifiers {
    let amount = min(1, max(0, (220 - gapMilliseconds) / 150))
    return Modifiers(level: 1 - 0.22 * amount, length: 1 - 0.25 * amount, brightness: 1 - 0.2 * amount)
  }

  func gain(baseFrequency: Double) -> Double {
    return min(1.5, max(0, level * (baseFrequency >= 2500 ? brightness : 1)))
  }
}

enum Theme: String, CaseIterable {
  case `default`
  case press

  var masterGain: Double {
    switch self {
    case .default: 0.306
    case .press: 0.499
    }
  }

  func selectLayers(modifiers: Modifiers) -> [Layer] {
    let pitch = modifiers.clampedPitch
    let length = modifiers.clampedLength

    switch self {
    case .default:
      return [
        .noise(
          filterType: .bandpass,
          frequency: 2800 * pitch,
          q: 2.2,
          envelope: Envelope(attack: 0.001, decay: 0.008 * length, peak: 0.16 * modifiers.gain(baseFrequency: 2800))
        ),
        .tone(
          frequency: Glide(from: 664 * pitch, to: 415 * pitch, duration: 0.018),
          envelope: Envelope(attack: 0.001, decay: 0.016 * length, peak: 0.03 * modifiers.gain(baseFrequency: 415))
        )
      ]

    case .press:
      return [
        .noise(
          filterType: .bandpass,
          frequency: 4800 * pitch,
          q: 8,
          envelope: Envelope(attack: 0.001, decay: 0.006 * length, peak: 0.12 * modifiers.gain(baseFrequency: 4800))
        ),
        .noise(
          filterType: .bandpass,
          frequency: 3240 * pitch,
          q: 2,
          envelope: Envelope(attack: 0.001, decay: 0.006 * length, peak: 0.06 * modifiers.gain(baseFrequency: 3240))
        ),
        .tone(
          frequency: Glide(from: 1120 * pitch, to: 700 * pitch, duration: 0.018),
          envelope: Envelope(attack: 0.001, decay: 0.015 * length, peak: 0.02 * modifiers.gain(baseFrequency: 1120))
        )
      ]
    }
  }
}

enum Renderer {
  private static let roomSendGain = 0.08
  private static let roomImpulseResponseDuration = 0.25
  private static let roomPredelay = 0.008
  private static let roomSendThreshold = 1e-9
  private static let busGain = 4.0 * pow(10, 3.5 / 20)

  static func render(_ layers: [Layer], masterGain: Double, outputGain: Double, seed: UInt64) -> StereoSignal {
    let frameCount = Int(Configuration.renderDuration * Configuration.sampleRate)

    var randomNumberGenerator = SplitMix64(state: seed)
    var dry = mix(layers, frameCount: frameCount, using: &randomNumberGenerator)

    for frame in dry.indices {
      dry[frame] *= masterGain
    }

    let leftImpulseResponse = makeRoomImpulseResponse(using: &randomNumberGenerator)
    let rightImpulseResponse = makeRoomImpulseResponse(using: &randomNumberGenerator)

    var sendFilter = Biquad(type: .lowpass, frequency: 3500, q: -3)

    let send = dry.map { sendFilter.process($0 * roomSendGain) }
    let wetLeft = convolve(send, with: leftImpulseResponse)
    let wetRight = convolve(send, with: rightImpulseResponse)
    let outputBusGain = busGain * outputGain

    return StereoSignal(
      left: zip(dry, wetLeft).map { ($0 + $1) * outputBusGain },
      right: zip(dry, wetRight).map { ($0 + $1) * outputBusGain }
    )
  }

  private static func mix(
    _ layers: [Layer],
    frameCount: Int,
    using randomNumberGenerator: inout SplitMix64
  ) -> [Double] {
    var output = [Double](repeating: 0, count: frameCount)

    for layer in layers {
      switch layer {
      case .tone(let frequency, let envelope):
        var phase = 0.0

        for frame in 0..<frameCount {
          let time = Double(frame) / Configuration.sampleRate

          if time >= envelope.stopTime {
            break
          }

          output[frame] += sin(phase) * envelope.value(at: time)
          phase += 2 * .pi * frequency.value(at: time) / Configuration.sampleRate
        }

      case .noise(let filterType, let frequency, let q, let envelope):
        var filter = Biquad(type: filterType, frequency: frequency, q: q)

        for frame in 0..<frameCount {
          let time = Double(frame) / Configuration.sampleRate

          if time >= envelope.stopTime {
            break
          }

          let noise = Double.random(in: -1...1, using: &randomNumberGenerator)

          output[frame] += filter.process(noise) * envelope.value(at: time)
        }
      }
    }

    return output
  }

  private static func makeRoomImpulseResponse(using randomNumberGenerator: inout SplitMix64) -> [Double] {
    let decayRate = (60.0 / 20) * log(10)

    var impulseResponse = (0..<Int(roomImpulseResponseDuration * Configuration.sampleRate)).map { frame -> Double in
      let time = Double(frame) / Configuration.sampleRate

      guard time >= roomPredelay else {
        return 0
      }

      let noise = Double.random(in: -1...1, using: &randomNumberGenerator)

      return noise * exp(-decayRate * time / roomImpulseResponseDuration)
    }

    let normalization = 1 / sqrt(impulseResponse.reduce(0) { $0 + $1 * $1 })

    for frame in impulseResponse.indices {
      impulseResponse[frame] *= normalization
    }

    return impulseResponse
  }

  private static func convolve(_ signal: [Double], with impulseResponse: [Double]) -> [Double] {
    let lastAudibleFrame = signal.lastIndex { abs($0) > roomSendThreshold } ?? 0

    var output = [Double](repeating: 0, count: signal.count)

    for frame in 0...lastAudibleFrame where signal[frame] != 0 {
      let sample = signal[frame]

      for offset in 0..<min(impulseResponse.count, signal.count - frame) {
        output[frame + offset] += sample * impulseResponse[offset]
      }
    }

    return output
  }
}

enum WAVFile {
  private static let channelCount: UInt16 = 2
  private static let bitsPerSample: UInt16 = 16
  private static let blockAlignment = channelCount * bitsPerSample / 8
  private static let silenceThreshold = pow(10, -90.0 / 20)
  private static let fadeOutDuration = 0.005

  static func write(_ signal: StereoSignal, to url: URL) throws -> (duration: Double, peakDecibels: Double) {
    let frameCount = audibleFrameCount(of: signal)
    let fadeOutFrameCount = Int(fadeOutDuration * Configuration.sampleRate)

    var sampleData = Data(capacity: frameCount * Int(blockAlignment))

    for frame in 0..<frameCount {
      let fade =
        frame >= frameCount - fadeOutFrameCount ? Double(frameCount - frame) / Double(fadeOutFrameCount) : 1

      for sample in [signal.left[frame], signal.right[frame]] {
        sampleData.appendLittleEndian(Int16(max(-32768, min(32767, (sample * fade * 32767).rounded()))))
      }
    }

    try (header(sampleDataByteCount: sampleData.count) + sampleData).write(to: url)

    let peak = max(
      signal.left.prefix(frameCount).map(abs).max() ?? 0,
      signal.right.prefix(frameCount).map(abs).max() ?? 0
    )

    return (Double(frameCount) / Configuration.sampleRate, 20 * log10(peak))
  }

  private static func audibleFrameCount(of signal: StereoSignal) -> Int {
    let lastAudibleFrame = max(
      signal.left.lastIndex { abs($0) > silenceThreshold } ?? 0,
      signal.right.lastIndex { abs($0) > silenceThreshold } ?? 0
    )
    return lastAudibleFrame + 1
  }

  private static func header(sampleDataByteCount: Int) -> Data {
    var header = Data(capacity: 44)
    header.append(contentsOf: "RIFF".utf8)
    header.appendLittleEndian(UInt32(36 + sampleDataByteCount))
    header.append(contentsOf: "WAVE".utf8)
    header.append(contentsOf: "fmt ".utf8)
    header.appendLittleEndian(UInt32(16))
    header.appendLittleEndian(UInt16(1))
    header.appendLittleEndian(channelCount)
    header.appendLittleEndian(UInt32(Configuration.sampleRate))
    header.appendLittleEndian(UInt32(Configuration.sampleRate) * UInt32(blockAlignment))
    header.appendLittleEndian(blockAlignment)
    header.appendLittleEndian(bitsPerSample)
    header.append(contentsOf: "data".utf8)
    header.appendLittleEndian(UInt32(sampleDataByteCount))

    return header
  }
}

struct Options {
  private static let usageDescription = """
    Usage:
      \(ProcessInfo.processInfo.processName) [options] <theme> <output-directory>

    Arguments:
      <theme>                 Cue theme (\(Theme.allCases.map(\.rawValue).joined(separator: ", ")))
      <output-directory>      Directory to write the WAV files to (created if needed)

    Options:
      -p, --up-pitch <ratio>  Set mouse-up pitch relative to mouse-down [default: \(Configuration.defaultUpPitch)]
      -g, --up-gap <ms>       Set mouse down-to-up delay for repeat softening [default: \(Int(Configuration.defaultUpGapMilliseconds))]
      -d, --gain <dB>         Set gain above theme base level [default: \(Int(Configuration.defaultGainDecibels))]
      -h, --help              Show this help message
    """

  var theme: Theme
  var outputDirectory: URL
  var upPitch = Configuration.defaultUpPitch
  var upGapMilliseconds = Configuration.defaultUpGapMilliseconds
  var gainDecibels = Configuration.defaultGainDecibels

  init(arguments: some Sequence<String>) {
    var arguments = arguments.makeIterator()
    var positionalArguments: [String] = []

    while let argument = arguments.next() {
      switch argument {
      case "-p", "--up-pitch":
        self.upPitch = Self.number(from: arguments.next(), for: argument)

      case "-g", "--up-gap":
        self.upGapMilliseconds = Self.number(from: arguments.next(), for: argument)

      case "-d", "--gain":
        self.gainDecibels = Self.number(from: arguments.next(), for: argument)

      case "-h", "--help":
        print(Self.usageDescription)
        exit(EXIT_SUCCESS)

      default:
        guard !argument.hasPrefix("-") else {
          Self.printUsageErrorAndExit("Unknown argument: \(argument)")
        }

        positionalArguments.append(argument)
      }
    }

    guard positionalArguments.count == 2 else {
      Self.printUsageErrorAndExit("Expected a theme and an output directory.")
    }

    guard let theme = Theme(rawValue: positionalArguments[0].lowercased()) else {
      Self.printUsageErrorAndExit(
        "Invalid theme '\(positionalArguments[0])'. Expected one of: \(Theme.allCases.map(\.rawValue).joined(separator: ", "))."
      )
    }

    self.theme = theme
    self.outputDirectory = URL(filePath: positionalArguments[1], directoryHint: .isDirectory)
  }

  private static func number(from value: String?, for argument: String) -> Double {
    guard let value else {
      printUsageErrorAndExit("Missing value for '\(argument)'.")
    }

    guard let number = Double(value), number.isFinite else {
      printUsageErrorAndExit("Invalid value for '\(argument)': \(value). Expected a number.")
    }

    return number
  }

  private static func printUsageErrorAndExit(_ message: String) -> Never {
    Log.error("Error: \(message)\n\n\(usageDescription)")
    exit(EX_USAGE)
  }
}

@main
enum GenerateClickSounds {
  static func main() {
    let options = Options(arguments: CommandLine.arguments.dropFirst())
    let outputGain = pow(10, options.gainDecibels / 20)
    let upModifiers = Modifiers.repeatSoftening(gapMilliseconds: options.upGapMilliseconds)
    let variants: [(fileName: String, pitch: Double, modifiers: Modifiers)] = [
      ("left-click-down.wav", Configuration.leftPitch, Modifiers()),
      ("left-click-up.wav", Configuration.leftPitch * options.upPitch, upModifiers),
      ("right-click-down.wav", Configuration.rightPitch, Modifiers()),
      ("right-click-up.wav", Configuration.rightPitch * options.upPitch, upModifiers)
    ]
    let fileNameWidth = variants.map(\.fileName.count).max() ?? 0

    do {
      try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)

      for (index, variant) in variants.enumerated() {
        var modifiers = variant.modifiers
        modifiers.pitch = variant.pitch

        let signal = Renderer.render(
          options.theme.selectLayers(modifiers: modifiers),
          masterGain: options.theme.masterGain,
          outputGain: outputGain,
          seed: Configuration.randomSeed + UInt64(index)
        )

        let (duration, peakDecibels) = try WAVFile.write(
          signal,
          to: options.outputDirectory.appending(path: variant.fileName)
        )

        let fileName = variant.fileName.padding(toLength: fileNameWidth, withPad: " ", startingAt: 0)
        let milliseconds = (duration * 1000).formatted(.number.precision(.fractionLength(0)))
        let peak = peakDecibels.formatted(.number.precision(.fractionLength(1)))

        print("\(fileName)  \(milliseconds) ms  peak \(peak) dBFS")
      }
    } catch {
      Log.error("Error: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
    }
  }
}
