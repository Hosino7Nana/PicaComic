import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:html/parser.dart';
import '../res.dart';
import 'fetch_data.dart';
import 'hitomi_models.dart';

/// 用于 hitomi.la 的网络请求类
///
/// 请不要直接Copy这里的代码, 因为部分接口调用我的服务器端爬虫, 我的服务器仅用于PicaComic项目
///
/// Please do not copy the code here,
/// because part of the interface calls my server-side crawler,
/// and my server is only used for the PicaComic project
class HiNetwork{
  factory HiNetwork() => cache==null ? (cache=HiNetwork._create()) : cache!;

  HiNetwork._create();

  static HiNetwork? cache;

  final baseUrl = "https://hitomi.la/";

  ///基本的get请求
  Future<Res<String>> get(String url) async{
    try{
      var dio = Dio();
      dio.options.headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36",

      };
      var res = await dio.get(url);
      return Res(res.data.toString());
    }
    catch(e){
      return Res(null, errorMessage: e.toString()=="null"?"未知错误":e.toString());
    }
  }

  ///从一个漫画列表中获取所有的漫画
  Future<Res<ComicList>> getComics(String url) async{
    var comicList = ComicList(url);
    var res = await loadNextPage(comicList);
    if(res.error){
      return Res(null, errorMessage: res.errorMessage!);
    }else{
      return Res(comicList);
    }
  }

  Future<Res<bool>> loadNextPage(ComicList comicList) async{
    if(comicList.toLoad >= comicList.total) return Res(false);
    var comicIds = await fetchComicData(comicList.url, comicList.toLoad, maxLength: comicList.total);
    if(comicIds.error){
      return Res(false, errorMessage: comicIds.errorMessage!);
    }
    comicList.total = int.parse(comicIds.subData);
    int loadingItem = 0;
    for(var id in comicIds.data){
      if(loadingItem > 5){
        //同时加载过多会导致卡顿
        await Future.delayed(const Duration(milliseconds: 500));
      }
      loadingItem++;
      getComicInfoBrief(id.toString()).then((comic){
        if(! comic.error){
          comicList.comics.add(comic.data);
          loadingItem--;
        }else{
          //不管了
          loadingItem--;
        }
      });
    }
    //设置一个计时器, 限制等待时间, 避免一些特殊情况导致卡住
    int timer = 0;
    while(loadingItem != 0){
      timer++;
      await Future.delayed(const Duration(milliseconds: 500));
      if(timer > 17){
        return Res(null, errorMessage: "请求超时");
      }
    }
    comicList.toLoad += 100;
    return Res(true);
  }

  ///获取一个漫画的简略信息
  Future<Res<HitomiComicBrief>> getComicInfoBrief(String id) async{
    var res = await get("https://ltn.hitomi.la/galleryblock/$id.html");
    if(res.error){
      return Res(null, errorMessage: res.errorMessage!);
    }
    try{
      var comicDiv = parse(res.data);
      var name = comicDiv.querySelector("h1.lillie > a")!.text;
      var link = comicDiv.querySelector("h1.lillie > a")!.attributes["href"]!;
      link = baseUrl + link;
      var artist = comicDiv.querySelector("div.artist-list")!.text;
      var cover = comicDiv.querySelector("div.dj-img1 > picture > source")!.attributes["data-srcset"]!;
      cover = cover.substring(2);
      cover = "https://a$cover";
      cover = cover.replaceAll(RegExp(r"2x.*"), "");
      cover = cover.removeAllWhitespace;
      var table = comicDiv.querySelectorAll("table.dj-desc > tbody");
      String type = "", lang = "";
      var tags = <Tag>[];
      for (var tr in table) {
        if (tr.firstChild!.text == "Type") {
          type = tr.children[1].text;
        } else if (tr.firstChild!.text == "Language") {
          lang = tr.children[1].text;
        } else if (tr.firstChild!.text == "Tags") {
          for (var liA in tr.querySelectorAll("td.relatedtags > ul > li > a")) {
            tags.add(Tag(liA.text, liA.attributes["href"]!));
          }
        }
      }
      var time = comicDiv.querySelector("div.dj-content > p")!.text;
      return Res(HitomiComicBrief(name, type, lang, tags, time, artist, link, cover));
    }
    catch(e){
      return Res(null, errorMessage: "解析失败: ${e.toString()}");
    }
  }

  ///搜索Hitomi
  ///
  /// 此函数通过服务器端爬虫进行获取数据
  ///
  /// hitomi搜索功能过于复杂, 通过大量前端js进行, 因此在服务器端使用模拟浏览器方式进行爬虫
  Future<Res<List<HitomiComicBrief>>> search(String keyword, int page) async{
    dynamic res;
    try{
      var dio = Dio();
      dio.options.responseType = ResponseType.plain;
      res = await dio
          .post("https://api.kokoiro.xyz/hitomi", data: {"keyword": keyword, "page": page});
    }
    catch(e){
      return Res(null, errorMessage: e.toString()=="null"?"网络错误":e.toString());
    }
    try{
      var document = parse(res.data);
      var comics = <HitomiComicBrief>[];
      for (var comicDiv in document.querySelectorAll("div.gallery-content > div")) {
        if (comicDiv.className == "search-message" && comicDiv.text == "No results") {
          return Res(comics, subData: 1);
        }
        var name = comicDiv.querySelector("h1.lillie > a")!.text;
        var link = comicDiv.querySelector("h1.lillie > a")!.attributes["href"]!;
        link = baseUrl + link;
        var artist = comicDiv.querySelector("div.artist-list")!.text;
        var cover =
            comicDiv.querySelector("div.dj-img1 > picture > source")!.attributes["data-srcset"]!;
        cover = cover.substring(2);
        cover = "https://$cover";
        cover = cover.replaceAll(RegExp(r"2x.*"), "");
        cover = cover.removeAllWhitespace;
        var table = comicDiv.querySelectorAll("table.dj-desc > tbody");
        String type = "", lang = "";
        var tags = <Tag>[];
        for (var tr in table) {
          if (tr.firstChild!.text == "Type") {
            type = tr.children[1].text;
          } else if (tr.firstChild!.text == "Language") {
            lang = tr.children[1].text;
          } else if (tr.firstChild!.text == "Tags") {
            for (var liA in tr.querySelectorAll("td.relatedtags > ul > li > a")) {
              tags.add(Tag(liA.text, liA.attributes["href"]!));
            }
          }
        }
        var time = comicDiv.querySelector("div.dj-content > p")!.text;
        comics.add(HitomiComicBrief(name, type, lang, tags, time, artist, link, cover));
      }
      int maxPage;
      var links = document.querySelectorAll("div.page-container > ul > li > a");
      maxPage = int.parse(links.last.text);
      return Res(comics, subData: maxPage);
    }
    catch(e){
      return Res(null, errorMessage: "解析错误: $e");
    }
  }

  ///获取漫画信息
  ///
  /// 为了避免不必要的网络请求, 需要传入漫画标题
  Future<Res<HitomiComic>> getComicInfo(String url, String name) async{
    var id = RegExp(r"\d+(?=\.html)").firstMatch(url)![0]!;
    var res = await get("https://ltn.hitomi.la/galleries/$id.js");
    if(res.error){
      return Res(null, errorMessage: res.errorMessage!);
    }
    //返回一个js脚本, 图片url也在这里面
    //直接将前面的"var galleryinfo = "删掉, 然后作为json解析即可
    var data = res.data.substring(res.data.indexOf('{'));
    var json = const JsonDecoder().convert(data);
    var tags = <Tag>[];
    var files = <HitomiFile>[];

    for(var tag in json["tags"]??[]){
      tags.add(Tag(tag["tag"], "$baseUrl${tag["url"]}"));
    }

    for(var file in json["files"]??[]){
      files.add(HitomiFile(file["name"], file["hash"],
          file["haswebp"]==1, file["hasavif"]==1, file["height"], file["width"], id));
    }
    return Res(HitomiComic(
      id,
      name,
      List<int>.from(json["related"]),
      json["type"],
      List<String>.from((json["artists"] as List<dynamic>).map((e) => e["artist"]).toList()),
      json["language_localname"],
      tags,
      json["date"],
      files
    ));
  }
}

class HitomiDataUrls{
  static String homePageAll = 'https://ltn.hitomi.la/index-all.nozomi';
  static String homePageCn = "https://ltn.hitomi.la/index-chinese.nozomi";
  static String homePageJp = "https://ltn.hitomi.la/index-japanese.nozomi";
  static String todayPopular = "https://ltn.hitomi.la/popular/today-all.nozomi";
  static String weekPopular = "https://ltn.hitomi.la/popular/week-all.nozomi";
  static String monthPopular = "https://ltn.hitomi.la/popular/month-all.nozomi";
  static String yearPopular = "https://ltn.hitomi.la/popular/year-all.nozomi";
}