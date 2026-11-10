extends Node
## Original pixel art, defined as palette-indexed ASCII grids and baked into
## textures at startup. Nearest-neighbour filtering keeps every pixel crisp.

const PALETTE := {
	"k": "#141018", "K": "#08060a", "x": "#000000",
	"s": "#d8a880", "S": "#a87858",
	"h": "#5a3a22",
	"r": "#a8302a", "R": "#6a1a1a",
	"g": "#c0c8d0", "G": "#7a8290", "m": "#4a505a",
	"w": "#f0ece0",
	"b": "#8a5a34", "B": "#4a3018",
	"n": "#4f8a3a", "N": "#2a4a22",
	"p": "#7050b0", "P": "#3a2860", "v": "#a88ae0",
	"y": "#e8c050", "Y": "#9a7020",
	"o": "#ff9a3a", "O": "#c04a10",
	"c": "#90e0ff", "C": "#3a7aa0",
	"e": "#ff3a2a", "E": "#80ff60",
	"z": "#e0d8c0", "Z": "#9a9078",
	"u": "#4a6ab0", "U": "#22305a",
	"l": "#8aa070", "L": "#5a7048",
	"q": "#7a6a5a", "Q": "#4a4038",
	"t": "#3a9a8a", "T": "#1a5a50",
	"f": "#a0c040", "F": "#607a20",
	"i": "#f4a8c8", "I": "#c06088", "j": "#d08a4a", "J": "#8a5228",
}

const SPRITES := {
	"warrior": [
		"................",
		"......kkkk......",
		".....kgggGk.....",
		"....kgggggGk....",
		"....kgkkkkGk....",
		"....kGmxxmGk....",
		".....kGGGGk.....",
		"...kkkrrrRkkk...",
		"..kgGkrryRkGgk..",
		"..kGmkrrrRkmGk..",
		"..kkkkrrrRkkkk..",
		"....kbBybBbk....",
		"....kGGkkGGk....",
		"....kGmk.kGmk...",
		"....kmmk.kmmk...",
		"....kkkk.kkkk...",
	],
	"ranger": [
		"................",
		"......kkkk......",
		".....kNnnnk.....",
		"....kNnnnnnk....",
		"....kNnssnNk....",
		"....kNsxsxNk....",
		"....kNnssnNk....",
		"...kNNkbbkNNk...",
		"..kNnkbBbbknNk..",
		"..kNnkbbyBknNk..",
		"..kNnkbBbbknNk..",
		"...kkkBbbBkkk...",
		"....kbbkkbbk....",
		"....kbBk.kbBk...",
		"....kBBk.kBBk...",
		"....kkkk.kkkk...",
	],
	"mage": [
		"........kk......",
		".......kPk......",
		"......kPpk......",
		".....kPppPk.....",
		"....kPpppppk....",
		"....kPkkkkPk....",
		"....kPxcxcPk....",
		"....kPkkkkPk....",
		"...kPppyppPPk...",
		"..kPpppyppppPk..",
		"..kspppyppppsk..",
		"...kPppyppPPk...",
		"...kPpppppPPk...",
		"..kPPppppppPPk..",
		"..kPPPPPPPPPPk..",
		"...kkkkkkkkkk...",
	],
	"ghoul": [
		"................",
		"................",
		".....kkkkk......",
		"....klllllk.....",
		"...klelleLk.....",
		"...kllllllk.....",
		"...kLxxxxLk.....",
		"..kkLLlllLkk....",
		".klkLlllllLklk..",
		".kl.kLlllLk.lk..",
		".kk.kLllLLk.kk..",
		"....kRLLLRk.....",
		"....kLk.kLk.....",
		"...klLk.kLlk....",
		"...kkkk.kkkk....",
		"................",
	],
	"rat": [
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"........kk.kk...",
		".......kqqkqqk..",
		"..kkkkkqqqqqek..",
		".kQkqqqqqqqqqqk.",
		"kQ.kqqqqqqqqqk..",
		"k...kQqqqqqQk...",
		".....kqk.kqk....",
		".....kk...kk....",
		"................",
	],
	"skeleton_archer": [
		"................",
		"......kkkk......",
		".....kzzzzk.....",
		"....kzzzzzzk....",
		"....kzexxezk....",
		"....kzzzzzzk....",
		".....kzxzxk.....",
		"......kzzk......",
		"....kkzzzzkk....",
		"...kz.kzZk.zk...",
		"...kz.kzZk.zk...",
		"...kk.kzzk.kk...",
		"......kzzk......",
		".....kz..zk.....",
		".....kz..zk.....",
		".....kk..kk.....",
	],
	"skeleton": [
		"................",
		"......kkkk......",
		".....kzzzzk.....",
		"....kzzzzzzk....",
		"....kzcxxczk....",
		"....kzzzzzzk....",
		".....kzxzxk.....",
		"..kkk.kzzk......",
		".kGGk.kzzzzkk...",
		".kGmk.kzZk.zk...",
		".kGGkkkzZk.zk...",
		"..kkk.kzzk.kk...",
		"......kzzk......",
		".....kz..zk.....",
		".....kz..zk.....",
		".....kk..kk.....",
	],
	"cultist": [
		"................",
		"......kkkk......",
		".....kRRRRk.....",
		"....kRrrrrRk....",
		"....kRkkkkRk....",
		"....kRkokoRk....",
		"....kRrkkrRk....",
		"...kRrrrrrrRk...",
		"..kRrrrYrrrrRk..",
		"..ksRrrYrrrRsk..",
		"...kRrrYrrrRk...",
		"...kRrrrrrrRk...",
		"..kRRrrrrrrRRk..",
		"..kRRRRRRRRRRk..",
		"...kkkkkkkkkk...",
		"................",
	],
	"bloater": [
		"................",
		"................",
		"......kkkk......",
		"....kkffffkk....",
		"...kfffEfEffk...",
		"..kffffffffffk..",
		"..kfFfxxxxfFfk..",
		".kffFffffffFffk.",
		".kfffFfFfFfFffk.",
		".kfFffffffffFfk.",
		".kffFfFfffFffFk.",
		"..kfFffffffFfk..",
		"..kkFFfffffFkk..",
		"....kkFFFFkk....",
		"......kkkk......",
		"................",
	],
	"brute": [
		"......................",
		"........kkkkkk........",
		".......kllllllk.......",
		"......kllellelLk......",
		"......kLlllllLLk......",
		"......kLxwxwxLLk......",
		"...kkkkLLlllLLkkkk....",
		"..kGgGGkLLLLLkGGgGk...",
		".kGggGmklllllkmGggGk..",
		".kGGGmkllllllLkmGGGk..",
		".kmmkkLllRRllLLkkmmk..",
		"..kk.kLlllllllLk.kk...",
		"....kkLLlllllLLkk.....",
		"...klk.kLLLLLLk.klk...",
		"...kllk.kBbBbk.kllk...",
		"...kllk.kBBBBk.kllk...",
		"....kk.kLLkkLLk.kk....",
		".......kLLk.kLLk......",
		"......kLLLk.kLLLk.....",
		"......kkkkk.kkkkk.....",
		"......................",
		"......................",
	],
	"warden": [
		"............................",
		"...........kkkkkk...........",
		"..........kgggggGk..........",
		".........kgggggggGk.........",
		".........kgGkkkkGGk.........",
		".........kGkcxxckGk.........",
		".........kGGkkkkGGk.........",
		"..........kGGGGGGk..........",
		"......kkkkkTttttTkkkkk......",
		".....kgggGkTttttTkGgggk.....",
		"....kggggGmkTttTkmGggggk....",
		"....kGGGGmkgGttGgkmGGGGk....",
		"....kmmmmkkGgttgGkkmmmmk....",
		"....kGgk.kGGgttgGGk.kgGk....",
		"....kGgk.kmGGttGGmk.kgGk....",
		"....kGgk.kTmGGGGmTk.kgGk....",
		"....ksSk.kTTmmmmTTk.kSsk....",
		".....kk..kTtTTTTtTk..kk.....",
		".........kTttTTttTk.........",
		".........kTtTkkTtTk.........",
		".........kGGk..kGGk.........",
		".........kGGk..kGGk.........",
		".........kGmk..kGmk.........",
		"........kGGmk..kGGmk........",
		"........kmmmk..kmmmk........",
		"........kkkkk..kkkkk........",
		"............................",
		"............................",
	],
	"dummy": [
		"................",
		".......kk.......",
		"......kbbk......",
		".....kbBBbk.....",
		".....kbxxbk.....",
		"......kbbk......",
		"..kkkkkbbkkkkk..",
		".kbbbbbBBbbbbbk.",
		"..kkkkbbbbkkkk..",
		"......kbBk......",
		".....kbbbbk.....",
		".....kbBBbk.....",
		"......kBBk......",
		"......kbbk......",
		".....kBBBBk.....",
		"....kkkkkkkk....",
	],
	"assassin": [
		"................",
		"......kkkk......",
		".....kmmmmk.....",
		"....kmmmmmmk....",
		"....kmkkkkmk....",
		"....kmkekekk....",
		"....kkrrrrkk....",
		"...kgkmmmmkgk...",
		"..kgk.kmmmk.kgk.",
		"..kk..kmrmk..kk.",
		"......kmmmk.....",
		".....kmmkmmk....",
		".....kmk.kmk....",
		"....kmmk.kmmk...",
		"....kkk...kkk...",
	],
	"shieldbearer": [
		"................",
		"......kkkk......",
		".....kzzzzk.....",
		"....kzexxezk....",
		"....kzzzzzzk....",
		".....kzxzxk.....",
		"..kkkkkzzk......",
		".kGGGGkzzzzkk...",
		".kGgggkzZk.zk...",
		".kGgygkzZk.zk...",
		".kGgggkzzk.kk...",
		".kGgggkzzk......",
		".kGGGGkz..zk....",
		"..kkkkkz..zk....",
		".....kk..kk.....",
	],
	"necromancer": [
		"................",
		"......kkkk......",
		".....kPPPPk.....",
		"....kPPPPPPk....",
		"....kPkkkkPk....",
		"....kPkEkEPk....",
		"....kPPkkPPk....",
		"...kPzPPPPzPk...",
		"..kPPzPPPPzPPk..",
		"..kEkPPzzPPkEk..",
		"...kPPPzzPPPk...",
		"...kPPPPPPPPk...",
		"..kPPPPPPPPPPk..",
		"..kPPPzPPzPPPk..",
		"...kkkkkkkkkk...",
	],
	"bat": [
		"................",
		"................",
		"................",
		"................",
		"k....kkkk....k..",
		"kk..kPPPPk..kk..",
		"kPk.kPePeP.kPk..",
		"kPPkkPPPPPkkPPk.",
		".kPPPPPPPPPPPk..",
		"..kkPPkkkPPkk...",
		"....kk...kk.....",
	],
	"gravemaw": [
		"..........................",
		"..........kkkkkk..........",
		".......kkkQQQQQQkkk.......",
		"......kQQqqqqqqqqQQk......",
		".....kQqqqqqqqqqqqqqQk....",
		"....kQqqqekqqqqqkeqqqQk...",
		"....kQqqqqqqqqqqqqqqqQk...",
		"...kQqqkwkwkwkwkwkwkqqQk..",
		"...kQqkRRRRRRRRRRRRRkqQk..",
		"...kQqkRrrrrrrrrrrrRkqQk..",
		"...kQqkRrRRRRRRRRRrRkqQk..",
		"...kQqkwkwkwkwkwkwkwkqQk..",
		"...kQqqqqqqqqqqqqqqqqqQk..",
		"....kQqqQqqqQqqqQqqqqQk...",
		"....kQqqqqqqqqqqqqqqqQk...",
		"...kQQqqqQqqqqqQqqqqqQQk..",
		"..kQQqqqqqqqqqqqqqqqqqqQQk",
		"..kQqqQqqqqQqqqqQqqqqQqqQk",
		".kBBQQqqqqqqqqqqqqqqqqQQBBk",
		"kBbbBBQQQQQQQQQQQQQQQQBBbbBk",
		"kBbbbbBBBBBBBBBBBBBBBBBbbbbBk",
		".kkkkkkkkkkkkkkkkkkkkkkkkkkk",
	],
	"construct": [
		"..........kkkkkkkk..........",
		".........kGGGGGGGGk.........",
		"........kGgggggggGGk........",
		"........kGgkkkkkkgGk........",
		"........kGgkoyyokgGk........",
		"........kGGkkkkkkGGk........",
		"....kkkkkmGGGGGGGGmkkkkk....",
		"...kGGGGkmGmmmmmmGmkGGGGk...",
		"..kGgggGkGmkkkkkkmGkGgggGk..",
		"..kGgmgGkGkooooookGkGgmgGk..",
		"..kGgggGkGkoyyyyokGkGgggGk..",
		"..kGGGGGkGkoyyyyokGkGGGGGk..",
		"..kmmmmkkGkoooooookGkkmmmk..",
		"..kGGGk.kGmkkkkkkmGk.kGGGk..",
		"..kGGGk.kGGGGGGGGGGk.kmmmk..",
		"..kmmmk.kmGmmmmmmGmk.kkkkk..",
		"..kkkkk.kGGk....kGGk........",
		".......kGGGk....kGGGk.......",
		".......kGmmk....kmmGk.......",
		"......kGGGGk....kGGGGk......",
		"......kkkkkk....kkkkkk......",
	],
	"demon": [
		"...kk..................kk...",
		"...kRk................kRk...",
		"....kRk..............kRk....",
		"....kRRk..kkkkkkkk..kRRk....",
		".....kRRkkrrrrrrrrkkRRk.....",
		"......kkrrrrrrrrrrrrkk......",
		".......krrkyrrrrykrrk.......",
		".......krrrrrrrrrrrrk.......",
		"..kk...krrkwwwwwwkrrk...kk..",
		".kRRk...krrrrrrrrrrk...kRRk.",
		"kRRRRk.kkrrrrrrrrrrkk.kRRRRk",
		"kRRRRRkrrRrrrrrrrrRrrkRRRRRk",
		"kRRRRRkrrrRRrrrrRRrrrkRRRRRk",
		".kRRRRkrrrrrRyyRrrrrrkRRRRk.",
		"..kRRRkkrrrrRyyRrrrrkkRRRk..",
		"...kRk.krrrrrRRrrrrrk.kRk...",
		"....k..kRrrrrrrrrrrRk..k....",
		".......kRRrrrkkrrrRRk.......",
		"........kRRrk..krRRk........",
		"........krrRk..kRrrk........",
		".......kRRRk....kRRRk.......",
		".......kkkkk....kkkkk.......",
	],
	"turret": [
		"................",
		"................",
		"..kk........kk..",
		"..kbk......kbk..",
		"...kbk....kbk...",
		"....kbkkkkbk....",
		".....kBGGBk.....",
		"..kkkkGggGkkkk..",
		".kgggggggggggk..",
		"..kkkkGggGkkkk..",
		".....kBbbBk.....",
		"....kbBkkBbk....",
		"...kbBk..kBbk...",
		"..kbBk....kBbk..",
		"..kkk......kkk..",
		"................",
	],
	"mine": [
		"..........",
		"...kkkk...",
		"..kGmmGk..",
		".kGmeemGk.",
		".kmmeemmk.",
		".kGmmmmGk.",
		"..kGmmGk..",
		"...kkkk...",
		"..........",
		"..........",
	],
	"npc_jeweller": [
		"................",
		"......kkkk......",
		".....kPpppk.....",
		"....kPpppppk....",
		"....khsssshk....",
		"....kssxsxsk....",
		"....khsssshk....",
		"...kkppccppkk...",
		"..kppppccppppk..",
		"..kspppvvpppsk..",
		"...kpppvvpppk...",
		"...kppyeyyppk...",
		"...kppppppppk...",
		"...kPPPPPPPPk...",
		"....kkkkkkkk....",
		"................",
	],
	"npc_merchant": [
		"................",
		"......kkkk......",
		".....kYyyyk.....",
		"....kYyyyyyk....",
		"....khsssshk....",
		"....kssxsxsk....",
		"....khsssshk....",
		"...kkuuyyuukk...",
		"..kuuuuyyuuuuk..",
		"..ksuuuyyuuusk..",
		"...kuuuyyuuuk...",
		"...kuubBbBuuk...",
		"...kuuuuuuuuk...",
		"...kUUUUUUUUk...",
		"....kkkkkkkk....",
		"................",
	],
	"npc_smith": [
		"................",
		"......kkkk......",
		".....khhhhk.....",
		"....khsssshk....",
		"....kssxsxsk....",
		"....khssssh k...",
		"....khhhhhhk....",
		"...kkBbbbbBkk...",
		"..ksBbBBBBbBsk..",
		"..ksBbbbbbbBsk..",
		"...kBbbbbbbBk...",
		"...kBBBBBBBBk...",
		"....kmmkkmmk....",
		"....kmmk.kmmk...",
		"....kkkk.kkkk...",
		"................",
	],
	# ---------------- pets (small, cute, cosmetic)
	"pet_dog": [
		"............",
		".kk......kk.",
		"kJjk....kjJk",
		"kJjjkkkkjjJk",
		".kjjjjjjjjk.",
		".kjxjjjjxjk.",
		".kjjjkkjjjk.",
		"..kjwwwwjk..",
		".kjjjjjjjjkk",
		"kjjjjjjjjjjk",
		"kjjjjjjjjjk.",
		".kjk.kk.kjk.",
		"..k......k..",
	],
	"pet_cat": [
		"............",
		".k........k.",
		".kQk....kQk.",
		".kqqkkkkqqk.",
		".kqqqqqqqqk.",
		".kqEqqqqEqk.",
		".kqqqiiqqqk.",
		"..kqqqqqqk..",
		"..kqwwwwqk.k",
		".kqqwwwwqqkq",
		".kqqqqqqqqk.",
		".kqk.kk.kqk.",
		"..k......k..",
	],
	"pet_frog": [
		"............",
		"............",
		"..kk....kk..",
		".kwxk..kxwk.",
		".knnkkkknnk.",
		"knnnnnnnnnnk",
		"knnnnnnnnnnk",
		"knNkkkkkkNnk",
		".knnnnnnnnk.",
		"kknfffffnkk.",
		"knnkkkkkknnk",
		".kk......kk.",
		"............",
	],
	"pet_slime": [
		"............",
		"............",
		"............",
		".....kk.....",
		"....kcck....",
		"...kcwcck...",
		"..kccccccK..",
		".kcxccccxcK.",
		".kccckkcccK.",
		"kcccccccccCk",
		"kCcccccccCCk",
		".kkkkkkkkkk.",
		"............",
	],
	"pet_robot": [
		".....e......",
		".....k......",
		"...kkkkkk...",
		"..kggggggk..",
		"..kgkkkkgk..",
		"..kgcGGcgk..",
		"..kgkkkkgk..",
		"...kkmmkk...",
		"..kggggggk..",
		".kGkgyygkGk.",
		"..kggggggk..",
		"..kmk..kmk..",
		"..kk....kk..",
	],
	"pet_goblin": [
		"............",
		"....kkkk....",
		"k..knnnnk..k",
		"knknnnnnnknk",
		".knnxnnxnnk.",
		"..knnnnnnk..",
		"..knnwwnnk..",
		"...kkkkkk...",
		"..kbbbbbbk..",
		".knbbyybbnk.",
		"..kbbbbbbk..",
		"..knk..knk..",
		"..kk....kk..",
	],
	"pet_fox": [
		"............",
		".k........k.",
		"kok......kok",
		"kookkkkkkook",
		".kooooooook.",
		".koxooooxok.",
		"..kwwkkwwk..",
		"...kwwwwk...",
		"..koooooook.",
		".koooooooookw",
		".kooowwoooko",
		".kok.kk.kok.",
		"..k......k..",
	],
	"pet_bunny": [
		"..kk...kk...",
		".kwik.kwik..",
		".kwik.kwik..",
		".kwwk.kwwk..",
		"..kwwkwwk...",
		".kwwwwwwwk..",
		".kwxwwwxwk..",
		".kwwwiwwwk..",
		"..kwwwwwk...",
		".kwwwwwwwk..",
		"kwwwwwwwwwk.",
		".kwk.k.kwk..",
		"..k.....k...",
	],
	"pet_hedgehog": [
		"............",
		"............",
		"...k.k.k....",
		"..kQkQkQk...",
		".kQqQqQqQk..",
		"kQqQqQqQqjk.",
		"kqQqQqQjjjjk",
		"kQqQqQjjxjjk",
		"kqQqQjjjjjjx",
		".kQqjjjjjjk.",
		"..kjk..kjk..",
		"...k....k...",
		"............",
	],
	"pet_dragon": [
		"............",
		"..k......k..",
		".kfk....kfk.",
		"..kkkkkkkk..",
		".kffffffffk.",
		".kfxfffxffk.",
		"..kfffffffk.",
		"k.kffoofffk.",
		"FkkffoofffkF",
		"FfkffoofffkF",
		".kfffffffk.k",
		"..kfk..kfkfk",
		"..kk....kk..",
	],
	"pet_axolotl": [
		"............",
		"I.........I.",
		"Ik.kkkkk.kI.",
		"IkkiiiiikkI.",
		".kiiiiiiik..",
		"Ikixiiixik.I",
		".kiiiIiiik..",
		"..kiiiiik...",
		".kiiiiiiikk.",
		"kiiiiiiiiiik",
		".kiiiiiiik..",
		".kik.k.kik..",
		"..k.....k...",
	],
	"pet_ghost": [
		"............",
		"....kkkk....",
		"...kwwwwk...",
		"..kwwwwwwk..",
		".kwwxwwxwwk.",
		".kwwwwwwwwk.",
		".kwwwkkwwwk.",
		".kwwwwwwwwk.",
		".kwwwwwwwwk.",
		".kwwwwwwwwk.",
		".kwkwwkwwkw.",
		"..k.kk.kk.k.",
		"............",
	],
	"pet_owl": [
		"............",
		".kk......kk.",
		".kbkkkkkkbk.",
		"..kbbbbbbk..",
		".kwwbbbbwwk.",
		".kwxwbbwxwk.",
		".kwwwyywwwk.",
		"..kbbyybbk..",
		".kbzbzbzbbk.",
		".kbbzbzbzbk.",
		".kbbbbbbbbk.",
		"..kykkkkyk..",
		"............",
	],
	"pet_mushroom": [
		"............",
		"...kkkkkk...",
		"..krwrrrrk..",
		".krrrrrwrrk.",
		"krwrrrrrrrrk",
		"krrrrwrrrwrk",
		".kkkkkkkkkk.",
		"..kzzzzzzk..",
		"..kzxzzxzk..",
		"..kzzzzzzk..",
		"..kzzzzzzk..",
		"..kZk..kZk..",
		"...k....k...",
	],
	"pet_bat": [
		"............",
		"....k..k....",
		"....kk.kk...",
		"k..kPPPPk..k",
		"kk.kPePeP.kk",
		"kPkkPPPPPkkPk",
		"kPPPkPPPkPPPk",
		"kPPkPPPPPkPPk",
		".kk.kPPPk.kk.",
		".....kPk.....",
		"......k......",
		"............",
		"............",
	],
	"pet_mimic": [
		"............",
		"............",
		".kkkkkkkkkk.",
		"kbbbbbbbbbbk",
		"kbBBBBBBBBbk",
		"kYYYYYYYYYYk",
		"kwkwkwkwkwkk",
		"kRRRRRRRRRRk",
		"kwkwkwkwkwkk",
		"kYYYYYYYYYYk",
		"kbbbbbbbbbbk",
		".kbk....kbk.",
		"..k......k..",
	],
	"pet_mimic_chest": [
		"............",
		"............",
		"............",
		".kkkkkkkkkk.",
		"kppppppppppk",
		"kpPPPPPPPPpk",
		"kvvvvvvvvvvk",
		"kppppyyppppk",
		"kppppYYppppk",
		"kpPPPPPPPPpk",
		"kvvvvvvvvvvk",
		"kkkkkkkkkkkk",
		"............",
	],
	"npc_petkeeper": [
		"................",
		"......kkkk......",
		".....knnnnk.....",
		"....knnnnnnk....",
		"....khsssshk....",
		"....kssxsxsk....",
		"....khsiishk....",
		"...kkllllllkk...",
		"..kllljjjjlllk..",
		"..ksllljjlllsk..",
		"...kllljjlllk...",
		"...kllbBbBllk.kk",
		"...kllllllllkkjk",
		"...kLLLLLLLLk.kk",
		"....kkkkkkkk....",
		"................",
	],
	"npc_restorer": [
		"................",
		"......kkkk......",
		".....kZzzzk.....",
		"....kZzzzzzk....",
		"....khsssshk....",
		"....kssxsxsk....",
		"....khsssshk....",
		"...kkzzyyzzkk.k.",
		"..kzzzzyyzzzzkjk",
		"..kszzzyyzzzskjk",
		"...kzzzyyzzzk.jk",
		"...kzzbBbBzzk.ek",
		"...kzzzzzzzzk.k.",
		"...kZZZZZZZZk...",
		"....kkkkkkkk....",
		"................",
	],
	"npc_collector": [
		"................",
		".....kkkkkk.....",
		"....kPPPPPPk....",
		"...kkkkkkkkkk...",
		"....kssxsxsk....",
		"....kSsssSsk....",
		".....kSsssk.....",
		"....kkPvvPkk..y.",
		"...kPPPvvPPPkkyk",
		"...kPPPvvPPPk.yk",
		"...ksPPvvPPsk.Yk",
		"....kPPyyPPk..k.",
		"....kPPPPPPk....",
		"....kPPkkPPk....",
		"....kkk..kkk....",
		"................",
	],
	"pentimento_wall": [
		"kkkkkkkkkkkkkkkk",
		"kqqcqqqqvqqqqcqk",
		"kqcCcqqqqqqvqqqk",
		"kqqcqqvvqqqqqqqk",
		"kqqqqvPvqqcqqqqk",
		"kqvqqqvqqcCcqqvk",
		"kqqqqqqqqqcqqqqk",
		"kqqcqqqvqqqqqcqk",
		"kqcCcqvPvqqqcCck",
		"kqqcqqqvqqqqqcqk",
		"kqqqqqqqqvqqqqqk",
		"kqvqqcqqvPvqqqqk",
		"kqqqcCcqqvqqqvqk",
		"kqqqqcqqqqqqqqqk",
		"kQQQQQQQQQQQQQQk",
		"kkkkkkkkkkkkkkkk",
	],
	"npc_drillmaster": [
		"................",
		"......kkkk......",
		".....kGggGk.....",
		"....kGggggGk....",
		"....kkkkkkkk....",
		"....kssxsxsk....",
		"....kshsshsk....",
		"...kkrrrrrrkk...",
		"..krrrryyrrrrk..",
		"..ksrrrryrrrsk..",
		"...krrrryrrrk...",
		"...krrbBbBrrk...",
		"...krrrrrrrrk...",
		"...kRRRRRRRRk...",
		"....kkkkkkkk....",
		"................",
	],
	"training_dummy": [
		"................",
		".....kkkkkk.....",
		"....kzzzzzzk....",
		"....kzkzzkzk....",
		".....kzzzzk.....",
		"..kkkkbbbbkkkk..",
		".kzzzkwwwwkzzzk.",
		".kzzkwrrrrwkzzk.",
		".kzzkwrwwrwkzzk.",
		".kzzkwrrrrwkzzk.",
		"..kkkkwwwwkkkk..",
		"......kbbk......",
		"......kbbk......",
		".....kbBBbk.....",
		"....kkkkkkkk....",
		"................",
	],
	"chest": [
		"................",
		"................",
		"................",
		"...kkkkkkkkkk...",
		"..kbbbbbbbbbbk..",
		"..kbBBBBBBBBbk..",
		"..kYYYYYYYYYYk..",
		"..kbbbbyybbbbk..",
		"..kbbbbYYbbbbk..",
		"..kbBBBBBBBBbk..",
		"..kbbbbbbbbbbk..",
		"..kYYYYYYYYYYk..",
		"..kkkkkkkkkkkk..",
		"................",
		"................",
		"................",
	],
	"torch": [
		"....o...",
		"...oyo..",
		"..oyyyo.",
		"..oywyo.",
		"...oyo..",
		"...kBk..",
		"...kbk..",
		"...kbk..",
	],
	"shrine": [
		"................",
		".......kk.......",
		"......kvvk......",
		".....kvccvk.....",
		"......kvvk......",
		".......kk.......",
		"......kGGk......",
		".....kGggGk.....",
		".....kGmmGk.....",
		".....kGggGk.....",
		".....kGmmGk.....",
		"....kGGggGGk....",
		"...kGGGGGGGGk...",
		"...kmmmmmmmmk...",
		"...kkkkkkkkkk...",
		"................",
	],
}

const ICONS := {
	"sword": ["..........kk", ".........kgk", "........kgk.", ".......kgk..", "......kgk...", ".....kgk....", "..k.kgk.....", "..kkgk......", "...kyk......", "..kbkkk.....", ".kbk..k.....", ".kk........."],
	"dagger": ["............", "............", ".........kk.", "........kgk.", ".......kgk..", "......kgk...", "...k.kgk....", "...kkgk.....", "....kyk.....", "...kbkk.....", "..kbk.......", "..kk........"],
	"axe": ["......kkk...", ".....kgggk..", "....kgGGgk..", "....kGkbkgk.", ".....kbk.kk.", "....kbk.....", "...kbk......", "..kbk.......", ".kbk........", "kbk.........", "kk..........", "............"],
	"mace": ["........kkk.", ".......kGgGk", ".......kgmgk", "......kkGgGk", ".....kbk.kk.", "....kbk.....", "...kbk......", "..kbk.......", ".kbk........", ".kk.........", "............", "............"],
	"greatsword": [".........kkk", "........kggk", ".......kggk.", "......kggk..", ".....kggk...", "....kggk....", ".k.kggk.....", ".kkggk......", "..kyyk......", ".kbkkk......", "kbk..k......", "kk.........."],
	"greataxe": [".....kkkk...", "....kggggk..", "...kgGGGgk..", "...kGkkbkgk.", "...kk.kbkkk.", ".....kbk....", "....kbk.....", "...kbk......", "..kbk.......", ".kbk........", "kbk.........", "kk.........."],
	"hammer": [".......kkkk.", "......kGggGk", "......kgmmgk", ".....kkGggGk", "....kbk.kkk.", "...kbk......", "..kbk.......", ".kbk........", "kbk.........", "kk..........", "............", "............"],
	"spear": ["..........kk", ".........kgk", "........kgk.", ".......kbk..", "......kbk...", ".....kbk....", "....kbk.....", "...kbk......", "..kbk.......", ".kbk........", "kbk.........", "kk.........."],
	"shield": ["............", ".kkkkkkkkkk.", ".kbbbbbbbbk.", ".kbGGGGGGbk.", ".kbGbbbbGbk.", ".kbGbyybGbk.", ".kbGbyybGbk.", "..kbGbbGbk..", "..kbGGGGbk..", "...kbbbbk...", "....kkkk....", "............"],
	"tower": [".kkkkkkkkkk.", ".kGGGGGGGGk.", ".kGgggggggk.", ".kGgmmmmggk.", ".kGgmyymggk.", ".kGgmyymggk.", ".kGgmmmmggk.", ".kGgggggggk.", ".kGgggggggk.", "..kGggggGk..", "...kGGGGk...", "....kkkk...."],
	"bow": ["....kkk.....", "...kbBkw....", "..kbk..w....", ".kbk...w....", ".kbk...w....", "kbk....w....", "kbk....w....", ".kbk...w....", ".kbk...w....", "..kbk..w....", "...kbBkw....", "....kkk....."],
	"longbow": ["...kkk......", "..kbBkw.....", ".kbk..w.....", ".kbk..w.....", "kbk...w.....", "kbk...w.....", "kbk...w.....", "kbk...w.....", ".kbk..w.....", ".kbk..w.....", "..kbBkw.....", "...kkk......"],
	"crossbow": ["............", ".kkkkkkkkk..", "kbbbbbbbbbk.", ".kkkkbkkkk..", "....kbk.....", "....kbk.....", "....kbk.....", "....kbk.....", "....kBk.....", "...kBBk.....", "...kkk......", "............"],
	"pistol": ["............", "............", "...kkkkkkkkk", "..kGmmmmmmmk", "..kbGGGGGGk.", "..kbbkkkkk..", ".kbbk.......", ".kbbk.......", "kbbk........", "kkkk........", "............", "............"],
	"rifle": ["............", "............", "............", "kkkkkkkkkkkk", "kbbbbGmmmmmk", "kbBBkkkkkkk.", "kbk.........", "kk..........", "............", "............", "............", "............"],
	"quiver": ["...w.w.w....", "...k.k.k....", "..kkkkkkk...", "..kbbbbbk...", "..kbBBBbk...", "..kbbbbbk...", "..kbYYYbk...", "..kbbbbbk...", "..kbBBBbk...", "..kbbbbbk...", "...kkkkk....", "............"],
	"wand": ["..........k.", ".........kck", "........kvk.", ".......kbk..", "......kbk...", ".....kbk....", "....kbk.....", "...kbk......", "..kbk.......", ".kBk........", ".kk.........", "............"],
	"staff": ["........kkk.", ".......kcvck", ".......kvcvk", "......kbkkk.", ".....kbk....", "....kbk.....", "...kbk......", "..kbk.......", ".kbk........", "kbk.........", "kk..........", "............"],
	"orb": ["............", "....kkkk....", "...kcvvck...", "..kcvwvvck..", "..kvvvvvvk..", "..kvvvvvck..", "...kcvvck...", "....kkkk....", "....kYYk....", "...kYyyYk...", "...kkkkkk...", "............"],
	"book": ["............", ".kkkkkkkkk..", ".kPPPPPPPPk.", ".kPpppppPPk.", ".kPpyyypPPk.", ".kPpypypPPk.", ".kPpyyypPPk.", ".kPpppppPPk.", ".kPPPPPPPPk.", ".kwwwwwwwwk.", ".kkkkkkkkkk.", "............"],
	"helm": ["............", "....kkkk....", "...kggggk...", "..kgggggGk..", "..kgGGGGGk..", "..kgkkkkGk..", "..kGmxxmGk..", "..kGGkkGGk..", "..kGk..kGk..", "...k....k...", "............", "............"],
	"coif": ["............", "....kkkk....", "...kGGGGk...", "..kGmGmGmk..", "..kmGmGmGk..", "..kGkkkkGk..", "..kmk..kmk..", "..kGk..kGk..", "..kmGkkGmk..", "...kkkkkk...", "............", "............"],
	"cap": ["............", "............", "....kkkk....", "...kbbbbk...", "..kbbbbbbk..", "..kbBBBBbk..", ".kbbbbbbbbk.", ".kkkkkkkkkk.", "............", "............", "............", "............"],
	"hood": ["............", ".....kk.....", "....kPpk....", "...kPpppk...", "..kPppppPk..", "..kPkkkkPk..", "..kPk..kPk..", "..kPk..kPk..", ".kPPk..kPPk.", ".kkkk..kkkk.", "............", "............"],
	"plate": ["............", ".kkk....kkk.", "kgGGk..kGGgk", "kGgGkkkkGgGk", ".kkgggggGkk.", "..kgGggGGk..", "..kgggggGk..", "..kgGggGGk..", "..kgggggGk..", "..kGGGGGGk..", "...kkkkkk...", "............"],
	"vest": ["............", ".kkk....kkk.", "kbbbk..kbbbk", "kbBbkkkkbBbk", ".kkbbbbbbkk.", "..kbBbbBbk..", "..kbbbbbbk..", "..kbBbbBbk..", "..kbbbbbbk..", "..kBBBBBBk..", "...kkkkkk...", "............"],
	"jerkin": ["............", ".kkk....kkk.", "kNnnk..knnNk", "kNnNkkkkNnNk", ".kknbbbbnkk.", "..knbBBbnk..", "..knbbbbnk..", "..knbBBbnk..", "..knbbbbnk..", "..kNNNNNNk..", "...kkkkkk...", "............"],
	"robe": ["............", ".kkk....kkk.", "kPppk..kppPk", "kPpPkkkkPpPk", ".kkppyyppkk.", "..kppyyppk..", "..kppyyppk..", "..kppyyppk..", ".kpppyypppk.", ".kPPPPPPPPk.", ".kkkkkkkkkk.", "............"],
	"gauntlet": ["............", "....kkkk....", "...kgGgGk...", "..kgGgGgGk..", "..kgggggGk..", "..kgggggGk..", "..kGgggGGk..", "...kGGGGk...", "...kmmmmk...", "...kGGGGk...", "...kkkkkk...", "............"],
	"glove": ["............", "....kkkk....", "...kbkbkbk..", "..kbkbkbkbk.", "..kbbbbbbbk.", "..kbbbbbbk..", "..kbbbbbbk..", "...kbbbbk...", "...kBBBBk...", "...kbbbbk...", "...kkkkkk...", "............"],
	"greaves": ["............", "...kkkk.....", "...kgGk.....", "...kgGk.....", "...kgGk.....", "...kgGk.....", "...kgGGkk...", "...kgggGGk..", "..kgggggGGk.", "..kGGGGGGGk.", "..kkkkkkkkk.", "............"],
	"boot": ["............", "...kkkk.....", "...kbBk.....", "...kbBk.....", "...kbBk.....", "...kbBk.....", "...kbBBkk...", "...kbbbBBk..", "..kbbbbbBBk.", "..kBBBBBBBk.", "..kkkkkkkkk.", "............"],
	"slipper": ["............", "............", "............", "............", "............", "....kkkk....", "...kppppk...", "..kpppppPkk.", ".kppppppppPk", ".kPPPPPPPPPk", ".kkkkkkkkkkk", "............"],
	"belt": ["............", "............", "............", "............", "kkkkkkkkkkkk", "kbbbbkkkbbbk", "kBBBBkyykBBk", "kbbbbkkkbbbk", "kkkkkkkkkkkk", "............", "............", "............"],
	"amulet": ["....kkkk....", "...k....k...", "..k......k..", "..k......k..", "...k....k...", "....kyyk....", "....kyyk....", "...kyeeyk...", "...kyeeyk...", "....kyyk....", ".....kk.....", "............"],
	"ring": ["............", "............", ".....kk.....", "....kcck....", "...kkcckk...", "..kyykkyyk..", "..ky....yk..", "..ky....yk..", "..kyy..yyk..", "...kyyyyk...", "....kkkk....", "............"],
	"charm": ["............", ".....kk.....", "....kzzk....", "...kzZZzk...", "...kzxxzk...", "...kzZZzk...", "....kzzk....", ".....kk.....", "....kbbk....", "....kbbk....", ".....kk.....", "............"],
	"gem": ["............", "............", "....kkkk....", "...kwggwk...", "..kwgwwggk..", "..kggwgggk..", "...kgggGk...", "....kgGk....", ".....kk.....", "............", "............", "............"],
	"gold": ["............", "............", "....kkkk....", "...kyyyyk...", "..kyYyyyyk..", "..kyyYyyyk..", "..kyyyYyyk..", "..kyyyyYyk..", "...kyyyyk...", "....kkkk....", "............", "............"],
	"rune": ["............", "....kkkk....", "...kwvvvk...", "..kwvkkvvk..", "..kvkvvkvk..", "..kvvkvkvk..", "..kvkvvkvk..", "..kvvkkvvk..", "...kvvvvk...", "....kkkk....", "............", "............"],
	"material": ["............", "............", ".....kk.....", "....kwwk....", "...kwwwvk...", "..kwwwvvvk..", "..kvwvvvvk..", "...kvvvvk...", "....kvvk....", ".....kk.....", "............", "............"],
	"flask_life": ["....kkkk....", "....kbbk....", "....kkkk....", "....kwwk....", "...kwrrwk...", "..kwrrrrrk..", "..krrrrrrk..", "..krrrrrRk..", "..kRrrrrRk..", "...kRRRRk...", "....kkkk....", "............"],
	"flask_mana": ["....kkkk....", "....kbbk....", "....kkkk....", "....kwwk....", "...kwuuwk...", "..kwuuuuuk..", "..kuuuuuuk..", "..kuuuuuUk..", "..kUuuuuUk..", "...kUUUUk...", "....kkkk....", "............"],
}

var _cache := {}
var light_tex: Texture2D
var soft_tex: Texture2D

func _ready() -> void:
	light_tex = _radial(128, 1.0)
	soft_tex = _radial(64, 0.6)
	load_render()
	load_manifest()

func _radial(size: int, power: float) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, power))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t

func _bake(rows: Array, palette_override: Dictionary = {}) -> ImageTexture:
	var h := rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, r.length())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if ch == "." or ch == " ":
				continue
			var hexc = palette_override.get(ch, PALETTE.get(ch, ""))
			if hexc == "":
				continue
			img.set_pixel(x, y, Color(hexc))
	return ImageTexture.create_from_image(img)

func sprite(id: String) -> Texture2D:
	var key := "s_" + id
	if not _cache.has(key):
		if SPRITES.has(id):
			_cache[key] = _bake(SPRITES[id])
		else:
			_cache[key] = _bake(SPRITES["ghoul"])
	return _cache[key]

func icon(id: String) -> Texture2D:
	var key := "i_" + id
	if not _cache.has(key):
		_cache[key] = _bake(ICONS.get(id, ICONS["charm"]))
	return _cache[key]

## Tinted variant (used for elite enemies and boss phases)
func tinted(id: String, tint: Color) -> Texture2D:
	var key := "t_%s_%s" % [id, tint.to_html()]
	if not _cache.has(key):
		var img: Image = sprite(id).get_image()
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0 and c.v > 0.12:
					img.set_pixel(x, y, c.lerp(tint, 0.35))
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]

# ------------------------------------------------------------- tiles
const TILE_PALETTES := {
	"crypt": {"floor": Color("#2c2a33"), "floor2": Color("#35323d"), "grout": Color("#1a1820"), "moss": Color("#2f3a2c"),
			"wall": Color("#4a4452"), "wall_hi": Color("#665f70"), "wall_dk": Color("#2a2630"), "void": Color("#0a090c")},
	"catacomb": {"floor": Color("#2a302a"), "floor2": Color("#323a31"), "grout": Color("#161b16"), "moss": Color("#3f5a2c"),
			"wall": Color("#4a5446"), "wall_hi": Color("#64705c"), "wall_dk": Color("#262c24"), "void": Color("#080a08")},
	"warren": {"floor": Color("#33261f"), "floor2": Color("#3d2d24"), "grout": Color("#1c130e"), "moss": Color("#5a2a1e"),
			"wall": Color("#5a3e30"), "wall_hi": Color("#785444"), "wall_dk": Color("#2e1f17"), "void": Color("#0b0705")},
	"sanctum": {"floor": Color("#2c2834"), "floor2": Color("#363040"), "grout": Color("#17141c"), "moss": Color("#5a2a3a"),
			"wall": Color("#504660"), "wall_hi": Color("#6c5f80"), "wall_dk": Color("#2a2434"), "void": Color("#09070c")},
	"vault": {"floor": Color("#262c38"), "floor2": Color("#2e3646"), "grout": Color("#141822"), "moss": Color("#6a5a20"),
			"wall": Color("#3e4a62"), "wall_hi": Color("#5a6a88"), "wall_dk": Color("#1f2534"), "void": Color("#06080c")},
	"abyss": {"floor": Color("#221c22"), "floor2": Color("#2a2028"), "grout": Color("#0e0a0e"), "moss": Color("#5a1020"),
			"wall": Color("#3a2430"), "wall_hi": Color("#56344a"), "wall_dk": Color("#1c1018"), "void": Color("#050304")},
	"hub": {"floor": Color("#3a3428"), "floor2": Color("#463e30"), "grout": Color("#241f18"), "moss": Color("#34402a"),
			"wall": Color("#5a5040"), "wall_hi": Color("#7a6c54"), "wall_dk": Color("#30281e"), "void": Color("#0c0b09")},
}

func floor_tile(pal: String, variant: int) -> Texture2D:
	var key := "f_%s_%d" % [pal, variant]
	if _cache.has(key):
		return _cache[key]
	var p: Dictionary = TILE_PALETTES.get(pal, TILE_PALETTES["crypt"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var c: Color = p["floor"] if (int(x / 8.0) + int(y / 8.0)) % 2 == 0 else p["floor2"]
			var n := rng.randf()
			if n < 0.12:
				c = c.darkened(0.12)
			elif n > 0.93:
				c = c.lightened(0.07)
			# flagstone grout lines, offset every other row
			var ox := 0 if int(y / 8.0) % 2 == 0 else 4
			if y % 8 == 0 or (x + ox) % 8 == 0:
				c = p["grout"]
			img.set_pixel(x, y, c)
	if variant == 1:
		for i in 6:
			img.set_pixel(rng.randi_range(1, 14), rng.randi_range(1, 14), p["moss"])
	elif variant == 2:
		var x0 := rng.randi_range(2, 12)
		var y0 := rng.randi_range(2, 12)
		for i in 5:
			img.set_pixel(clampi(x0 + i, 0, 15), clampi(y0 + (i % 2), 0, 15), p["grout"])
	elif variant == 3:
		for i in 3:
			var bx := rng.randi_range(2, 13)
			var by := rng.randi_range(2, 13)
			img.set_pixel(bx, by, Color("#c8c0a8"))
			img.set_pixel(bx + 1, by, Color("#9a9078"))
	_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]

func wall_tile(pal: String, top_only: bool) -> Texture2D:
	var key := "w_%s_%s" % [pal, str(top_only)]
	if _cache.has(key):
		return _cache[key]
	var p: Dictionary = TILE_PALETTES.get(pal, TILE_PALETTES["crypt"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var c: Color
			if top_only:
				c = p["wall_dk"]
				if rng.randf() < 0.1:
					c = c.lightened(0.05)
			else:
				c = p["wall"]
				var ox := 0 if int(y / 5.0) % 2 == 0 else 5
				if y % 5 == 0 or (x + ox) % 10 == 0:
					c = p["wall_dk"]
				elif y % 5 == 1:
					c = p["wall_hi"]
				if rng.randf() < 0.08:
					c = c.darkened(0.15)
				if y >= 14:
					c = p["wall_dk"].darkened(0.3)
			img.set_pixel(x, y, c)
	_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]

# ------------------------------------------------------------- sprite sheets (Phase V0)
# New art is PNG sprite sheets described by data/art/sprites.json, drawn at 32 px per
# cell and shown at ART_SCALE (0.5) inside the 16-unit gameplay grid, so with the camera's
# zoom of 2 one art pixel is one screen pixel at 1280x720. See docs/adr/0001-art-scale.md.
# Anything missing falls back to the ASCII art above (Art.sprite(fallback)).
const RENDER_PATH := "res://data/render.json"
const MANIFEST_PATH := "res://data/art/sprites.json"
const ASSET_ROOT := "res://assets/"
const PLACEHOLDER_ROOT := "res://assets/placeholders/"
const AnimRules = preload("res://scripts/gfx/anim_rules.gd")

var render := {}
var ART_SCALE := 0.5             # loaded from data/render.json "art_scale"
var manifest := {}
var placeholders_in_game := false   # render.json, or --art-placeholders on the command line
var force_fallback := false      # --art-fallback, or tests: ignore every sheet
var art_errors := []
var _defs := {}
var _frames := {}

func load_render() -> void:
	render = _read_json(RENDER_PATH)
	ART_SCALE = float(render.get("art_scale", 0.5))
	placeholders_in_game = bool(render.get("placeholders_in_game", false))
	var args := OS.get_cmdline_user_args()
	if args.has("--art-placeholders"):
		placeholders_in_game = true
	if args.has("--art-fallback"):
		force_fallback = true

func load_manifest() -> void:
	manifest = _read_json(MANIFEST_PATH)
	if not manifest.has("sprites"):
		manifest["sprites"] = {}
	clear_sheet_cache()

func clear_sheet_cache() -> void:
	_defs.clear()
	_frames.clear()

func camera_zoom() -> float:
	return float(render.get("camera_zoom", 2.0))

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		art_errors.append("missing " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var v = JSON.parse_string(f.get_as_text())
	if typeof(v) != TYPE_DICTIONARY:
		art_errors.append("bad json " + path)
		return {}
	return v

## The manifest entry with defaults filled in (same rules as tools/art_common.py).
func sprite_entry(id: String) -> Dictionary:
	var sprites: Dictionary = manifest.get("sprites", {})
	if not sprites.has(id):
		return {}
	var e: Dictionary = sprites[id]
	var out: Dictionary = manifest.get("defaults", {}).duplicate(true)
	for k in e:
		if k != "anims":
			out[k] = e[k]
	out["id"] = id
	if not out.has("frame"):
		out["frame"] = [64, 64]
	if not out.has("pivot"):
		out["pivot"] = [int(out["frame"][0]) / 2, int(out["frame"][1]) - 6]
	var anims := {}
	var ea: Dictionary = e.get("anims", {})
	for n in ea:
		var a: Dictionary = {"fps": float(out.get("fps", 10)), "loop": false}
		for k in ea[n]:
			a[k] = ea[n][k]
		if not a.has("file"):
			a["file"] = "sprites/%s/%s/%s_%s.png" % [out.get("category", "misc"), id, id, n]
		anims[n] = a
	out["anims"] = anims
	return out

## First id in `ids` (e.g. [enemy id, sprite id]) that has usable sheet art, resolved with
## loaded textures; {} when none (the caller keeps the old Sprite2D art).
func sprite_def(ids) -> Dictionary:
	if force_fallback:
		return {}
	if typeof(ids) == TYPE_STRING:
		ids = [ids]
	for id in ids:
		var d := _resolve(str(id))
		if not d.is_empty():
			return d
	return {}

## Resolves one entry: per animation, real art at assets/<file>, else (when placeholders
## are enabled) assets/placeholders/<file>. Usable when at least "idle" resolves.
func _resolve(id: String, allow_placeholders := false) -> Dictionary:
	var key := id + ("|ph" if (placeholders_in_game or allow_placeholders) else "")
	if _defs.has(key):
		return _defs[key]
	var out := {}
	var e := sprite_entry(id)
	if not e.is_empty():
		var fw := int(e["frame"][0])
		var fh := int(e["frame"][1])
		var rows := AnimRules.rows_needed(int(e.get("directions", 8)), bool(e.get("mirror", true)))
		var anims := {}
		var any_ph := false
		for n in e["anims"]:
			var a: Dictionary = e["anims"][n].duplicate()
			var tex: Texture2D = null
			var ph := false
			var real: String = ASSET_ROOT + str(a["file"])
			if ResourceLoader.exists(real):
				tex = load(real)
			elif placeholders_in_game or allow_placeholders:
				var pp: String = PLACEHOLDER_ROOT + str(a["file"])
				if ResourceLoader.exists(pp):
					tex = load(pp)
					ph = true
			if tex == null:
				continue
			var nf := int(a.get("frames", 1))
			if tex.get_width() < nf * fw or tex.get_height() < rows * fh:
				art_errors.append("%s/%s: sheet %dx%d is smaller than %d frames x %d rows of %dx%d" % [id, n, tex.get_width(), tex.get_height(), nf, rows, fw, fh])
				continue
			a["tex"] = tex
			a["placeholder"] = ph
			any_ph = any_ph or ph
			anims[n] = a
		if anims.has("idle"):
			out = e
			out["anims"] = anims
			out["rows"] = rows
			out["placeholder"] = any_ph
	_defs[key] = out
	return out

## Gallery / tests: resolve with placeholders allowed regardless of the in-game setting.
func sprite_def_any(id: String) -> Dictionary:
	return _resolve(id, true)

## SpriteFrames for a resolved def: animation "<anim>_<row>", one AtlasTexture per frame.
## Built once per def and shared by every actor using it.
func sprite_frames_for(d: Dictionary) -> SpriteFrames:
	var key := str(d.get("id", "")) + ("|ph" if d.get("placeholder", false) else "")
	if _frames.has(key):
		return _frames[key]
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	var fw := int(d["frame"][0])
	var fh := int(d["frame"][1])
	for n in d["anims"]:
		var a: Dictionary = d["anims"][n]
		for r in int(d.get("rows", 1)):
			var an := "%s_%d" % [n, r]
			sf.add_animation(an)
			sf.set_animation_loop(an, bool(a.get("loop", false)))
			sf.set_animation_speed(an, float(a.get("fps", 10)))
			for f in int(a.get("frames", 1)):
				var at := AtlasTexture.new()
				at.atlas = a["tex"]
				at.region = Rect2(f * fw, r * fh, fw, fh)
				sf.add_frame(an, at)
	_frames[key] = sf
	return sf
