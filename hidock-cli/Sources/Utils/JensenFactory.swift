import JensenUSB

public struct JensenFactory {
    public static var make: (Bool) -> Jensen = { verbose in
        return Jensen(verbose: verbose)
    }
}
