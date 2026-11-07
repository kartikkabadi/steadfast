import Foundation

struct PresetGroup: Identifiable {
    let name: String
    let domains: [String]
    var id: String { name }
}

enum Presets {
    static let groups: [PresetGroup] = [
        PresetGroup(name: "social", domains: [
            "x.com", "twitter.com", "instagram.com", "facebook.com", "threads.net", "threads.com",
            "snapchat.com", "tiktok.com", "bsky.app", "mastodon.social", "linkedin.com", "vk.com",
            "weibo.com", "lemon8-app.com", "truthsocial.com"
        ]),
        PresetGroup(name: "streaming", domains: [
            "youtube.com", "youtu.be", "twitch.tv", "netflix.com", "primevideo.com", "hotstar.com",
            "jiocinema.com", "hulu.com", "disneyplus.com", "max.com", "dailymotion.com",
            "vimeo.com", "kick.com", "sonyliv.com", "zee5.com", "crunchyroll.com", "tubitv.com",
            "pluto.tv", "peacocktv.com", "paramountplus.com", "tv.apple.com", "bilibili.com",
            "rumble.com", "dazn.com", "watch.plex.tv"
        ]),
        PresetGroup(name: "forums & feeds", domains: [
            "reddit.com", "old.reddit.com", "quora.com", "9gag.com", "tumblr.com", "pinterest.com",
            "news.ycombinator.com", "producthunt.com", "medium.com", "substack.com", "digg.com",
            "imgur.com", "ifunny.co", "letterboxd.com", "goodreads.com"
        ]),
        PresetGroup(name: "news", domains: [
            "news.google.com", "cnn.com", "bbc.com", "bbc.co.uk", "nytimes.com", "theguardian.com",
            "foxnews.com", "timesofindia.indiatimes.com", "hindustantimes.com", "ndtv.com",
            "indianexpress.com", "inshorts.com", "reuters.com", "apnews.com", "washingtonpost.com",
            "wsj.com", "bloomberg.com", "cnbc.com", "nbcnews.com", "abcnews.go.com", "aljazeera.com",
            "thehindu.com", "livemint.com", "news18.com", "indiatoday.in", "theverge.com", "buzzfeed.com"
        ]),
        PresetGroup(name: "shopping", domains: [
            "amazon.in", "amazon.com", "flipkart.com", "myntra.com", "ajio.com", "meesho.com",
            "nykaa.com", "ebay.com", "etsy.com", "aliexpress.com", "temu.com", "walmart.com",
            "target.com", "bestbuy.com", "shein.com", "asos.com", "zara.com", "hm.com", "ikea.com",
            "alibaba.com", "allegro.pl", "mercari.com", "poshmark.com", "snapdeal.com", "tatacliq.com"
        ]),
        PresetGroup(name: "games", domains: [
            "steampowered.com", "store.epicgames.com", "roblox.com", "crazygames.com", "poki.com",
            "chess.com", "lichess.org", "agar.io", "itch.io", "neal.fun", "steamcommunity.com",
            "fortnite.com", "minecraft.net", "ea.com", "ubisoft.com", "playstation.com", "xbox.com",
            "nintendo.com", "miniclip.com", "coolmathgames.com", "kongregate.com", "game8.co",
            "ign.com", "gamespot.com"
        ]),
        PresetGroup(name: "music & audio", domains: [
            "open.spotify.com", "music.apple.com", "music.youtube.com", "soundcloud.com", "bandcamp.com",
            "deezer.com", "tidal.com", "pandora.com", "music.amazon.com", "music.amazon.in",
            "jiosaavn.com", "gaana.com", "audiomack.com", "mixcloud.com", "last.fm"
        ]),
        PresetGroup(name: "sports", domains: [
            "espn.com", "espncricinfo.com", "cricbuzz.com", "sports.yahoo.com", "skysports.com",
            "cbssports.com", "bleacherreport.com", "theathletic.com", "flashscore.com", "sofascore.com",
            "nba.com", "nfl.com", "formula1.com", "fifa.com", "icc-cricket.com"
        ]),
        PresetGroup(name: "food delivery", domains: [
            "zomato.com", "swiggy.com", "ubereats.com", "doordash.com", "grubhub.com",
            "deliveroo.com", "just-eat.co.uk", "foodpanda.com", "seamless.com"
        ]),
        PresetGroup(name: "chat", domains: [
            "discord.com", "web.telegram.org", "web.whatsapp.com", "messenger.com", "web.snapchat.com",
            "groupme.com", "web.wechat.com"
        ]),
        PresetGroup(name: "dating", domains: [
            "tinder.com", "okcupid.com", "match.com", "badoo.com",
            "pof.com", "grindr.com"
        ]),
        PresetGroup(name: "AI tools", domains: [
            "chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com", "grok.com",
            "perplexity.ai", "poe.com", "character.ai", "chat.deepseek.com", "copilot.microsoft.com",
            "meta.ai", "chat.mistral.ai"
        ]),
        PresetGroup(name: "gambling", domains: [
            "bet365.com", "stake.com", "stake.bet", "betway.com", "1xbet.com", "draftkings.com",
            "fanduel.com", "pokerstars.com", "betfair.com", "betmgm.com", "williamhill.com",
            "888casino.com", "unibet.com", "betano.com"
        ]),
        PresetGroup(name: "adult", domains: [
            "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com", "youporn.com",
            "onlyfans.com", "fansly.com", "chaturbate.com"
        ])
    ]
    static let searchableDomains = Array(Set(groups.flatMap(\.domains))).sorted()

    private static let searchNames: [String: [String]] = [
        "hotstar.com": ["jiohotstar", "jio hotstar", "disney hotstar"],
        "primevideo.com": ["prime video", "amazon prime video"],
        "disneyplus.com": ["disney plus", "disney+"],
        "tv.apple.com": ["apple tv", "apple tv+"],
        "news.ycombinator.com": ["hacker news"],
        "news.google.com": ["google news"],
        "open.spotify.com": ["spotify"],
        "music.apple.com": ["apple music"],
        "music.youtube.com": ["youtube music"],
        "music.amazon.com": ["amazon music"],
        "music.amazon.in": ["amazon music"],
        "chatgpt.com": ["chat gpt"],
        "gemini.google.com": ["google gemini"],
        "copilot.microsoft.com": ["microsoft copilot"]
    ]

    static func matches(_ domain: String, query: String) -> Bool {
        domain.localizedCaseInsensitiveContains(query)
            || (searchNames[domain]?.contains { $0.localizedCaseInsensitiveContains(query) } ?? false)
    }
}
