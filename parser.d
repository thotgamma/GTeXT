//
//  parser.d
//  GTeXT
//
//  Created by thotgamma on 2016/02/04.
//
//	#このファイル:
//		input.gtの構文を解析し、必要な要素を抽出し格納する。
//
//	#コードの流れ:
//		1.入力ファイルからプリコマンド行だけを抽出し処理。この際本文は無視する。
//		2.入力ファイルから本文だけを抽出。この際プリコマンド行は無視する。
//		3.本文から数式を抽出(数式は"[]"内に記述)。
//		4.本文からコマンドを抽出。
//
//	#なぜプリコマンドと本文で解析の実行タイミングを分けるのか
//		A.プリコマンド行では本文をPDFに変換するのに必要な情報(例えば用紙サイズやフォントなど)を指定するため、
//			先に全てのプリコマンド行を捜査するため。
//

module parser;

import std.stdio;
import std.string;
import std.regex;
import std.conv;
import std.array;
import std.format;
import std.utf;
import std.algorithm;

import loadcmap;
public import fontanalyzer;

int[4][string] paperSizeDictionary;

//PDFの生成に必要な要素(これを集めるのが目的)
//先に初期値を代入しておく。
string title = "noname";
string author = "anonymous";
sentence[] sentences;
int[4] paperSize = [0, 0, 595, 842]; //a4
int[4] padding = [28, 28, 28, 28]; //10mmのパディング
int currentFontSize = 20;
string streamBuff;
uint pageWidth;
uint pageHeight;


//文章を要素ごとに分割する際、それを格納する構造体
struct sentence{
	string type;
	string content;
	string argument;
	this(string in0, string in1){
		type = in0;
		content = in1;
	}
}

struct style{
	uint fontSize;
	uint fontID;
	string fontName;
}
style[] styleStack;	//範囲指定子が使うやつ
style[] styleList;	//自分で命名したstyleを保存するやつ

//行ごとのまとまり
class outputline{
	int nextGap;
	double lineWidth;
	uint maxFontSize;
	string stream;
	string textAlign;
}
outputline[] outputlines;

//関数 parse
//
//input.gtを解析する。
//
//入力(ファイル)
//input.gt
//
//出力(グローバル)
//paperSize
//padding
//sentences
//
//

void parse(){

	//デバッグを素早く行うため入力ファイル名はあらかじめ記入しておいた
	string inputFile = "input.gt";

	auto fin = File(inputFile,"r");

	//cmapファイルをの読み込み
	loadcmap.loadcmap();

	//解析に使う変数
	string line;
	string currentmode = "normal";
	string buff;
	string precommand;
	string argument;

	bool beforeArgument = true;

	paperSizeDictionary = ["a4":[0,0,595,842]];

	writeln("本文の解析を開始します");
	writeln("プリコマンドを解析しています。");


	while(!fin.eof){
		line = fin.readln.chomp;	//.chompで改行コードを除去
		if(line.length >= 2){
			if(line[0 .. 2] == "#!"){
				//コマンド行
				line = line[2 .. $];
				foreach(str; line){
					if(beforeArgument == true){
						if(str == '('){
							beforeArgument = false;
						}else{
							precommand ~= str;
						}
					}else{
						if(str == ')'){
							auto argDict = argumentAnalyzer(argument);
							switch(precommand){
								case "title":
									title = argDict["_default_"];
									writeln("タイトル: " ~ title);
									break;
								case "author":
									author = argDict["_default_"];
									writeln("著者: " ~ author);
									break;
								case "paperSize":
									if("_default_" in argDict){
										writeln(argDict["_default_"] ~ "の紙の大きさを辞書から取得しています");
										paperSize = paperSizeDictionary[argDict["_default_"]];
										pageWidth = to!int(paperSize[2]);
										pageHeight= to!int(paperSize[3]);
										writeln("取得成功: " ~ to!string(pageWidth) ~ "x" ~ to!string(pageHeight));
									}else{
										pageWidth = to!int(argDict["width"]);
										pageHeight=to!int(argDict["height"]);
										writeln("ページサイズを手動で指定します(" ~ to!string(pageWidth) ~ "x" ~ to!string(pageHeight) ~ ")");
										paperSize = [0, 0, pageWidth, pageHeight];
									}
									break;
								case "padding":
									if("_default_" in argDict){
										int pad = to!int(argDict["_default_"]);
										padding = [pad,pad,pad,pad];
									}else{
										padding = [to!int(argDict["up"]),to!int(argDict["down"]),to!int(argDict["left"]),to!int(argDict["right"])];
									}
									writeln("パディングを設定します"
											~	"(天:" ~ to!string(padding[0])
											~ "mm 地:" ~ to!string(padding[1])
											~ "mm 左:" ~ to!string(padding[2])
											~ "mm 右:" ~ to!string(padding[3])
											~ "mm)");
									break;
								default:
									writeln("Error! 存在しないプリコマンド" ~ precommand);
									break;
							}
							precommand = "";
							argument = "";
							beforeArgument = true;
						}else{
							argument ~= str;
						}
					}
				}
				
			}
		}
	}

	writeln("本文を解析しています");

	//ファイル読み込みのシーカーを頭に戻す
	fin.rewind();

	while(!fin.eof){
		line = fin.readln.chomp;
		//コマンド行もしくは空行であればスキップ
		if(line.length == 0){
			//空行はパラグラフ変更である
			if(buff != ""){
				sentences ~= sentence("normal",buff);
				buff = "";
			}
			sentences ~= sentence("command","newparagraph");
			continue;
		}else if(line.length >= 2){
			if(line[0 .. 2] == "#!"){
				continue;
			}
		}

		//1文字ずつ処理する
		foreach(str;line){
			switch(currentmode){
				case "normal":
					if(str == '#'){
						if(buff != ""){
							sentences ~= sentence("normal",buff);
							buff = "";
						}
						currentmode = "command";
					}else if(str == '['){
						if(buff != ""){
							sentences ~= sentence("normal",buff);
							buff = "";
						}
						currentmode = "math";
					}else if(str == '{'){
						sentences ~= sentence("normal",buff);
						buff = "";
						sentences ~= sentence("command","beginRange");
					}else if(str == '}'){
						sentences ~= sentence("normal",buff);
						buff = "";
						sentences ~= sentence("command","endRange");
					}else{
						buff ~= str;
					}
					break;
				case "command":
					if(str == '['){
						sentences ~= sentence("command",buff);
						buff = "";
						currentmode = "math";
					}else if(str == ' '){
						sentences ~= sentence("command",buff);
						buff = "";
						currentmode = "normal";
					}else if(str == '('){
						sentences ~= sentence("command",buff);
						buff = "";
						currentmode = "argument";
					}else{
						buff ~= str;
					}
					break;
				case "math":
					if(str == ']'){
						sentences ~= sentence("math",buff);
						buff = "";
						currentmode = "normal";
					}else{
						buff ~= str;
					}
					break;
				case "argument":
					if(str == ')'){
						sentences[$-1].argument = buff;
						buff = "";
						currentmode = "normal";
					}else{
						buff ~= str;
					}
					break;
				default:
					break;
			}
		}
		if(currentmode == "command"){
			sentences ~= sentence("command",buff);
			buff = "";
			currentmode = "normal";
		}
	}
	if(buff != "")sentences ~= sentence(currentmode,buff);
	buff = "";
	currentmode = "normal";
	
	outputline newline = new outputline;
	double currentWidth;
	string stringbuff;
	uint currentFont;
	string currentAlign = "left";

	writeln("数式及びコマンドを処理しています");

	foreach(elem; sentences){
		if(elem.type == "normal"){
			foreach(str;array(elem.content)){
				string cid = string2cid(to!string(str));
				uint ciduint = to!uint(cid,16);
				uint advanceWidth = getAdvanceWidth(to!string(str),currentFont);
				currentWidth += to!double(currentFontSize)*to!double(advanceWidth)/to!double(fonts[currentFont].unitsPerEm);

				if(currentWidth > (paperSize[2] - padding[0] - padding[1] - 10)){ //改行するタイミング
					newline.stream ~= "<" ~ stringbuff ~ "> Tj\n";	// ┓
					newline.lineWidth = currentWidth;				// ┃
					outputlines ~= newline;							// ┃
					newline = new outputline;						// ┃改行処理
					currentWidth = 0;								// ┃
					stringbuff = "";								// ┛
				}

				//streamのイニシャライズ
				if(newline.stream == ""){
					newline.stream ~= "/F" ~ to!string(currentFont) ~ " " ~ to!string(currentFontSize) ~ " Tf ";
					newline.maxFontSize = currentFontSize;
					newline.textAlign = currentAlign;
				}

				stringbuff ~= cid;
				bool flag = true;;
				foreach(a;fonts[currentFont].widthCidMapping){
					if(a.cid == ciduint){
						flag = false;
						break;
					}
				}
				if(flag == true){
					fonts[currentFont].widthCidMapping ~= widthCidStruct(ciduint,advanceWidth);
				}
			}
			

		}else if(elem.type == "command"){
			switch(elem.content){
				case "beginRange":
					styleStack ~= style(currentFontSize,currentFont);
					break;
				case "endRange":
					currentFontSize = styleStack.back.fontSize;
					currentFont = styleStack.back.fontID;
					styleStack.popBack();
					if(stringbuff != ""){
						newline.stream ~= "<" ~ stringbuff ~ "> Tj ";
						stringbuff = "";
						newline.stream ~= "/F" ~ to!string(currentFont) ~ " " ~ to!string(currentFontSize) ~ " Tf ";
						if(currentFontSize > newline.maxFontSize){
							newline.maxFontSize = currentFontSize;
						}
					}
					break;
				case "newparagraph":
					newline.stream ~= "<" ~ stringbuff ~ "> Tj\n";	// ┓
					newline.lineWidth = currentWidth;				// ┃
					outputlines ~= newline;							// ┃
					newline = new outputline;						// ┃改行処理
					currentWidth = 0;								// ┃
					stringbuff = "";								// ┛
					break;
				case "br":
					if(elem.argument != ""){
						auto argDict = argumentAnalyzer(elem.argument);
						newline.nextGap = to!int(argDict["_default_"]);
					}
					newline.stream ~= "<" ~ stringbuff ~ "> Tj\n";	// ┓
					newline.lineWidth = currentWidth;				// ┃
					outputlines ~= newline;							// ┃
					newline = new outputline;						// ┃改行処理
					currentWidth = 0;								// ┃
					stringbuff = "";								// ┛
					break;
				case "pi":
					stringbuff ~= string2cid("π");
					stringbuff ~= string2cid(" ");
					currentWidth += currentFontSize*getAdvanceWidth("π",currentFont);
					break;
				case "setFontSize":
					auto argDict = argumentAnalyzer(elem.argument);
					currentFontSize = to!int(argDict["_default_"]);
					if(stringbuff != ""){
						newline.stream ~= "<" ~ stringbuff ~ "> Tj ";
						stringbuff = "";
						newline.stream ~= "/F" ~ to!string(currentFont) ~ " " ~ to!string(currentFontSize) ~ " Tf ";
						if(currentFontSize > newline.maxFontSize){
							newline.maxFontSize = currentFontSize;
						}
					}
					break;
				case "setFont":
					auto argDict = argumentAnalyzer(elem.argument);
					string newFontName = to!string(argDict["_default_"]);
					bool flag = false;
					foreach(uint i, font; fonts){
						if(font.fontName == newFontName){
							currentFont = i;
							flag = true;
							break;
						}
					}
					if(flag == false){
						addNewFont(newFontName);
						currentFont = to!uint(fonts.length-1);
					}
					if(stringbuff != ""){
						newline.stream ~= "<" ~ stringbuff ~ "> Tj ";
						stringbuff = "";
						newline.stream ~= "/F" ~ to!string(currentFont) ~ " " ~ to!string(currentFontSize) ~ " Tf ";
					}
					break;
				case "setAlign":
					auto argDict = argumentAnalyzer(elem.argument);
					currentAlign = to!string(argDict["_default_"]);
					newline.stream ~= "<" ~ stringbuff ~ "> Tj\n";	// ┓
					newline.lineWidth = currentWidth;				// ┃
					outputlines ~= newline;							// ┃
					newline = new outputline;						// ┃改行処理
					currentWidth = 0;								// ┃
					stringbuff = "";								// ┛
					break;
				default:
					break;
			}
		}
	}

	writeln("行の高さを計算しています");

	streamBuff ~= "BT\n";
	uint currentHeight = pageHeight - padding[3];
	foreach(uint i, eachLine; outputlines){
		if(i == 0){
			currentHeight -= eachLine.maxFontSize + fonts[currentFont].lineGap/fonts[currentFont].unitsPerEm;
		}else{
			currentHeight -= eachLine.maxFontSize + outputlines[i-1].nextGap + fonts[currentFont].lineGap/fonts[currentFont].unitsPerEm;
		}
		switch(eachLine.textAlign){
			case "left":
				streamBuff ~= "1. 0. 0. 1. " ~ to!string(padding[0]) ~ ". " ~ to!string(currentHeight) ~ ". Tm ";
				break;
				case "center":
				streamBuff ~= "1. 0. 0. 1. " ~ to!string(to!int((pageWidth -eachLine.lineWidth)/2)) ~ ". " ~ to!string(currentHeight) ~ ". Tm ";
				break;
			case "right":
				streamBuff ~= "1. 0. 0. 1. " ~ to!string(to!int(pageWidth -eachLine.lineWidth -padding[1])) ~ ". " ~ to!string(currentHeight) ~ ". Tm ";
				break;
			default:
				break;
		}
		
		streamBuff ~= eachLine.stream;
	}
	streamBuff ~= "ET\n";

	writeln("cidフォントの文字幅辞書を作っています。");
	
	foreach(font;fonts){
		sort!("a.cid < b.cid")(font.widthCidMapping);
		foreach(a; font.widthCidMapping){
			if(a.width==1000)continue;
			font.W ~= a.cid;
			font.W ~= a.cid;
			font.W ~= a.width;
		}
	}
}

//関数 argumentAnalyzer
//
//stringで表現された引数表現を連想配列に変換する
//入力形式は"key:value,key:value"
//また、keyが与えられず、"value"だけ与えられた場合はkeyが_default_と言う値で要素が一つだけ格納される。
//
//入力(引数)
//string in0		解析する前の文字列(e.g. "width:300, height:500")
//出力(戻り値)
//string[string]	鍵と値の連想配列(e.g. width->300, height->500)
//
string[string] argumentAnalyzer(string in0){

	if(indexOf(in0,",") == -1){
		return ["_default_":in0];
	}


	string[string] argument;

	string keyBuff;
	string valueBuff;

	const bool readKey = false;
	const bool readValue = true;
	bool mode = readKey;

	foreach(str; in0){
		if(str == ':'){
			mode = readValue;
		}else if(str == ','){
			mode = readKey;

			argument[keyBuff] = valueBuff;
			keyBuff = "";
			valueBuff = "";

		}else if(str == ' '){
			continue; //スペースは無視する
		}else{
			if(mode == readKey){
				keyBuff ~= str;
			}else{
				valueBuff ~= str;
			}
		}
	}
	argument[keyBuff] = valueBuff; //最後には","がないので別途記述

	return argument;

}

//関数 string2cid
//
//文字1文字を受け取り、cmap[]を参照することでその文字に対するCIDを取得する。
//
//入力(引数)
//string in0		文字1文字
//出力(戻り値)
//string CID
//
string string2cid(string in0){
	if(in0 == ""){
		return "";
	}
	auto writer = appender!string();
	string output;
	foreach(c; array(in0)) {
		foreach(b; [c].toUTF8) {
			formattedWrite(writer,"%x",b);
		}
	uint unicode = to!uint(writer.data,16);
	writer = appender!string();
	formattedWrite(writer,"%x",cmap[unicode]);
	output ~= rightJustify(writer.data,4,'0');
	writer = appender!string();
	}
	return output;
}
