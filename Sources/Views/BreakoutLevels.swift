//
//  BreakoutLevels.swift
//  FunNotch
//
//  Notch Breakout's boards, drawn as text so a level can be read — and
//  designed — at a glance. After the last one they come round again, every
//  brick taking one more hit each time.
//

enum BreakoutLevels {
    struct Board {
        let name: String
        let rows: [String]
    }

    /// Each row is fourteen cells:
    ///
    ///     .      empty
    ///     1 2 3  a brick that takes that many hits
    ///     #      steel, which never breaks and does not count towards a clear
    ///     X      explosive: takes its neighbours with it, and chains
    ///     $      gold, worth a hundred
    ///     ?      a mystery brick, which always drops a power-up
    static let boards: [Board] = [
        Board(name: "Warm-up", rows: [
            "11111111111111",
            "1111?1111?1111",
            "11111111111111",
            "11111111111111",
        ]),
        // The wall with the notch cut out of it.
        Board(name: "The Notch", rows: [
            "2222......2222",
            "22222....22222",
            "11111111111111",
            "1X11?1111?11X1",
            "11111111111111",
        ]),
        Board(name: "Checkers", rows: [
            "2.2.2.2.2.2.2.",
            ".2.2.2.2.2.2.2",
            "1.1.X.1.1.X.1.",
            ".1.1.?.?.1.1.1",
            "1.1.1.$.1.1.1.",
        ]),
        // Its head is full of explosives.
        Board(name: "Invader", rows: [
            "....?.....?...",
            ".....1...1....",
            "....2222222...",
            "...22.XXX.22..",
            "..11111111111.",
            "..1.1111111.1.",
        ]),
        // A steel floor with a way up at each wall, and the gold inside.
        Board(name: "Fortress", rows: [
            "22222222222222",
            "2#2$$?XX?$$2#2",
            "2#2222222222#2",
            "2############2",
            "11111111111111",
        ]),
        Board(name: "Diamond", rows: [
            "......22......",
            "....221122....",
            "$.2211XX1122.$",
            "....221122....",
            "......22......",
        ]),
        // Steel with gaps: the ball has to find its way up.
        Board(name: "Stripes", rows: [
            "33333333333333",
            "#.##.####.##.#",
            "22222?22?22222",
            ".##.##..##.##.",
            "11111111111111",
        ]),
        Board(name: "Heart", rows: [
            "..222....222..",
            ".22222..22222.",
            ".2222?XX?2222.",
            "..2222222222..",
            "....222222....",
            "......$$......",
        ]),
        // A breather before the loop comes round harder.
        Board(name: "Jackpot", rows: [
            "$.$.$.$.$.$.$.",
            ".?.$.$.?.$.$.?",
            "$.$.$.$.$.$.$.",
            ".1.1.1.1.1.1.1",
            "X.1.1.1.1.1.1X",
        ]),
    ]

    static func board(for level: Int) -> Board {
        boards[(max(level, 1) - 1) % boards.count]
    }

    /// Extra hits every brick takes once the boards have all been seen and
    /// come round again.
    static func toughening(for level: Int) -> Int {
        (max(level, 1) - 1) / boards.count
    }
}
