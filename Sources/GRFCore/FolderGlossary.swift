import Foundation

/// Local English hints for RO resource folders. Paths and original names never change.
public enum FolderGlossary {
    public static func english(for name: String) -> String? {
        translations[name.precomposedStringWithCanonicalMapping]
    }
    private static let translations: [String: String] = [
        "유저인터페이스": "User Interface", "아이템": "Items", "인간족": "Human", "여": "Female", "남": "Male",
        "_여": "Female", "_남": "Male", "여자": "Female", "남자": "Male", "악세사리": "Accessories", "액세서리": "Accessories",
        "로브": "Robe", "기타마을": "Other Towns", "몬스터": "Monsters", "필드바닥": "Ground Textures",
        "내부소품": "Interior Props", "외부소품": "Outdoor Props", "기타마을내부": "Other Town Interiors",
        "몸통": "Body", "몸": "Body", "머리": "Head", "머리통": "Head", "방패": "Shields", "무기": "Weapons",
        "기린의날개": "Kirin Wings", "아버지사랑날개2012": "Father's Love Wings 2012", "모험가배낭": "Adventurer Backpack",
        "타락천사의날개": "Fallen Angel Wings", "행복의날개": "Wings of Happiness", "천사날개": "Angel Wings",
        "루드라의날개": "Rudra Wings", "아미스트르가방": "Amistr Bag", "모로코": "Morocc", "모로코내부": "Morocc Interiors",
        "크루세이더": "Crusader", "페코페코_기사": "Peco Peco Knight", "기사": "Knight", "검사": "Swordsman",
        "이팩트": "Effects", "이펙트": "Effects", "신페코크루세이더": "New Peco Crusader", "구페코크루세이더": "Old Peco Crusader",
        "페이욘": "Payon", "페이욘내부": "Payon Interiors", "워터": "Water", "프론테라": "Prontera",
        "프론테라내부": "Prontera Interiors", "나무잡초꽃": "Trees, Grass, Flowers", "연금술사": "Alchemist",
        "상인": "Merchant", "제철공": "Blacksmith", "아인브로크": "Einbroch", "로그": "Rogue", "어세신": "Assassin",
        "몽크": "Monk", "세이지": "Sage", "도둑": "Thief", "라헬": "Rachel", "리히타르젠": "Lighthalzen",
        "게페니아": "Geffenia", "프리스트": "Priest", "크리스마스마을": "Christmas Village", "글래스트": "Glast Heim",
        "건너": "Gunner", "성직자": "Acolyte", "휘겔": "Hugel", "헌터": "Hunter", "중국": "China", "위저드": "Wizard",
        "마법사": "Mage", "궁수": "Archer", "아요타야": "Ayothaya", "해변마을": "Seaside Village", "초보자": "Novice",
        "전장": "Battleground", "유노추가": "Additional Juno", "슈퍼노비스": "Super Novice", "무명섬": "Nameless Island",
        "무희": "Dancer", "사막도시": "Desert City", "러시아": "Russia", "움발라": "Umbala", "니플헤임": "Niflheim",
        "타나토스": "Thanatos", "바드": "Bard", "유노": "Juno", "인던02": "Instance 02", "인던01": "Instance 01",
        "알데바란": "Aldebaran", "일본": "Japan", "토르화산": "Thor Volcano", "길드전": "Guild War", "대만": "Taiwan",
        "거북이섬": "Turtle Island", "어비스": "Abyss", "자와이": "Jawaii", "알베르타": "Alberta", "유페로스": "Juperos",
        "지하감옥": "Prison", "히나마쯔리": "Hinamatsuri", "게펜내부": "Geffen Interiors", "게펜": "Geffen", "닌자": "Ninja",
        "흑마법사방": "Dark Mage Room", "등대섬": "Lighthouse Island", "동굴마을": "Cave Village", "던전": "Dungeon",
        "용병": "Mercenaries", "알베르타내부": "Alberta Interiors", "글래지하수로": "Glast Heim Sewers", "운영자": "Game Master",
        "용암동굴": "Lava Cave", "워프대기실내부": "Warp Waiting Room", "집시마을": "Gypsy Village", "태권소년": "Taekwon Boy",
        "레인져늑대": "Ranger Wolf", "마도기어": "Mado Gear", "쉐도우체이서": "Shadow Chaser", "지하묘지": "Catacombs"
    ]
}
