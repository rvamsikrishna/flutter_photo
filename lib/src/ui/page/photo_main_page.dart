import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as prefix0;
import 'package:photo/src/delegate/badge_delegate.dart';
import 'package:photo/src/delegate/loading_delegate.dart';
import 'package:photo/src/engine/lru_cache.dart';
import 'package:photo/src/engine/throttle.dart';
import 'package:photo/src/entity/options.dart';
import 'package:photo/src/provider/config_provider.dart';
import 'package:photo/src/provider/gallery_list_provider.dart';
import 'package:photo/src/provider/i18n_provider.dart';
import 'package:photo/src/provider/selected_provider.dart';
import 'package:photo/src/ui/dialog/change_gallery_dialog.dart';
import 'package:photo_manager/photo_manager.dart';

part './main/bottom_widget.dart';
part './main/image_item.dart';

class PhotoMainPage extends StatefulWidget {
  final ValueChanged<List<AssetEntity>> onClose;
  final Options options;
  final List<AssetPathEntity> photoList;

  const PhotoMainPage({
    Key key,
    this.onClose,
    this.options,
    this.photoList,
  }) : super(key: key);

  @override
  _PhotoMainPageState createState() => _PhotoMainPageState();
}

class _PhotoMainPageState extends State<PhotoMainPage>
    with
        SelectedProvider,
        GalleryListProvider,
        prefix0.SingleTickerProviderStateMixin {
  Options get options => widget.options;

  I18nProvider get i18nProvider => ConfigProvider.of(context).provider;

  List<AssetEntity> list = [];

  Color get themeColor => options.themeColor;

  AssetPathEntity _currentPath = AssetPathEntity.all;

  bool _isInit = false;

  final List<Tab> _tabs = [
    Tab(text: 'Recent'),
    Tab(text: 'Camera'),
  ];
  TabController _tabController;

  AssetPathEntity get currentPath {
    if (_currentPath == null) {
      return null;
    }
    return _currentPath;
  }

  set currentPath(AssetPathEntity value) {
    _currentPath = value;
  }

  String get currentGalleryName {
    if (currentPath.isAll) {
      return i18nProvider.getAllGalleryText(options);
    }
    return currentPath.name;
  }

  GlobalKey scaffoldKey;
  ScrollController scrollController;

  bool isPushed = false;

  bool get useAlbum => widget.photoList == null || widget.photoList.isEmpty;

  Throttle _changeThrottle;

  @override
  void initState() {
    super.initState();
    _refreshList();
    scaffoldKey = GlobalKey();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (_tabController.indexIsChanging) {
          int currIndexindex = _tabController.index;

          switch (currIndexindex) {
            case 0:
              _onGalleryChange(this.galleryPathList[0]);
              break;
            case 1:
              _onGalleryChange(this.galleryPathList[1]);
              break;
          }
          selectedList.clear();
        }
      });

    scrollController = ScrollController();
    _changeThrottle = Throttle(onCall: _onAssetChange);
    PhotoManager.addChangeCallback(_changeThrottle.call);
    PhotoManager.startChangeNotify();
  }

  @override
  void dispose() {
    PhotoManager.removeChangeCallback(_changeThrottle.call);
    PhotoManager.stopChangeNotify();
    _changeThrottle.dispose();
    scrollController.dispose();
    _tabController.dispose();
    scaffoldKey = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var textStyle = TextStyle(
      color: options.textColor,
      fontSize: 18.0,
    );
    return Theme(
      data: Theme.of(context).copyWith(primaryColor: options.themeColor),
      child: DefaultTextStyle(
        style: textStyle,
        child: Scaffold(
          backgroundColor: Colors.black.withOpacity(0.5),
          body: Column(
            children: <Widget>[
              prefix0.Container(
                height: prefix0.MediaQuery.of(context).size.height / 3,
              ),
              Expanded(
                child: Container(
                  padding: prefix0.EdgeInsets.symmetric(horizontal: 15.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30.0),
                      topRight: Radius.circular(30.0),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      prefix0.SizedBox(height: 15.0),
                      prefix0.Row(
                        mainAxisAlignment:
                            prefix0.MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: options.textColor,
                            ),
                            onPressed: _cancel,
                          ),
                          FlatButton(
                            splashColor: Colors.transparent,
                            child: Text(
                              'Done',
                              style: selectedCount == 0
                                  ? textStyle.copyWith(
                                      color: options.disableColor)
                                  : textStyle,
                            ),
                            onPressed: selectedCount == 0 ? null : sure,
                          ),
                        ],
                      ),
                      prefix0.SizedBox(height: 15.0),
                      prefix0.TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: const Color.fromRGBO(216, 216, 216, 0.5),
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        indicatorColor: Colors.transparent,
                        labelColor: Colors.black,
                        unselectedLabelColor: Colors.black.withOpacity(0.3),
                        tabs: _tabs,
                      ),
                      prefix0.SizedBox(height: 15.0),
                      Expanded(
                        child: prefix0.TabBarView(
                          controller: _tabController,
                          children: <Widget>[
                            _buildBody(scrollController),
                            _buildBody(scrollController),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cancel() {
    selectedList.clear();
    widget.onClose(selectedList);
  }

  @override
  bool isUpperLimit() {
    var result = selectedCount == options.maxSelected;
    if (result) _showTip(i18nProvider.getMaxTipText(options));
    return result;
  }

  void sure() {
    widget.onClose?.call(selectedList);
  }

  void _showTip(String msg) {
    if (isPushed) {
      return;
    }
    Scaffold.of(scaffoldKey.currentContext).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(
            color: options.textColor,
            fontSize: 14.0,
          ),
        ),
        duration: Duration(milliseconds: 1500),
        backgroundColor: themeColor.withOpacity(0.7),
      ),
    );
  }

  void _refreshList() {
    if (!useAlbum) {
      _refreshListFromWidget();
      return;
    }

    _refreshListFromGallery();
  }

  Future<void> _refreshListFromWidget() async {
    galleryPathList.clear();
    galleryPathList.addAll(widget.photoList);
    this.list.clear();
    var assetList = await galleryPathList[0].assetList;
    _sortAssetList(assetList);
    this.list.addAll(assetList);
    setState(() {
      _isInit = true;
    });
  }

  Future<void> _refreshListFromGallery() async {
    List<AssetPathEntity> pathList;
    switch (options.pickType) {
      case PickType.onlyImage:
        pathList = await PhotoManager.getImageAsset();
        break;
      case PickType.onlyVideo:
        pathList = await PhotoManager.getVideoAsset();
        break;
      default:
        pathList = await PhotoManager.getAssetPathList();
    }

    if (pathList == null) {
      return;
    }

    options.sortDelegate.sort(pathList);

    galleryPathList.clear();
    galleryPathList.addAll(pathList);

    List<AssetEntity> imageList;

    if (pathList.isNotEmpty) {
      imageList = await pathList[0].assetList;
      _sortAssetList(imageList);
      _currentPath = pathList[0];
    }

    for (var path in pathList) {
      if (path.isAll) {
        path.name = i18nProvider.getAllGalleryText(options);
      }
    }

    this.list.clear();
    if (imageList != null) {
      this.list.addAll(imageList);
    }
    setState(() {
      _isInit = true;
    });
  }

  void _sortAssetList(List<AssetEntity> assetList) {
    options?.sortDelegate?.assetDelegate?.sort(assetList);
  }

  Widget _buildBody(ScrollController scrollController) {
    if (!_isInit) {
      return _buildLoading();
    }

    return GridView.builder(
      padding: prefix0.EdgeInsets.symmetric(vertical: 0.0, horizontal: 5.0),
      controller: scrollController,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: options.rowCount,
        childAspectRatio: options.itemRadio,
        crossAxisSpacing: options.padding,
        mainAxisSpacing: options.padding,
      ),
      itemBuilder: _buildItem,
      itemCount: list.length,
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    var data = list[index];
    var currentSelected = containsEntity(data);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          changeCheck(!currentSelected, data);
        },
        child: Stack(
          children: <Widget>[
            ImageItem(
              entity: data,
              themeColor: themeColor,
              size: options.thumbSize,
              loadingDelegate: options.loadingDelegate,
              badgeDelegate: options.badgeDelegate,
            ),
            _buildMask(containsEntity(data)),
            _buildSelected(data),
          ],
        ),
      ),
    );
  }

  _buildMask(bool showMask) {
    return IgnorePointer(
      child: AnimatedContainer(
        color: showMask ? Colors.black.withOpacity(0.5) : Colors.transparent,
        duration: Duration(milliseconds: 300),
      ),
    );
  }

  Widget _buildSelected(AssetEntity entity) {
    return Positioned(
      right: 0.0,
      width: 36.0,
      height: 36.0,
      child: _buildText(entity),
    );
  }

  Widget _buildText(AssetEntity entity) {
    var isSelected = containsEntity(entity);
    Widget child;
    BoxDecoration decoration;
    if (isSelected) {
      child = Text(
        (indexOfSelected(entity) + 1).toString(),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.0,
          color: options.textColor,
        ),
      );
      decoration =
          BoxDecoration(color: themeColor, shape: prefix0.BoxShape.circle);
    } else {
      decoration = BoxDecoration(
        shape: prefix0.BoxShape.circle,
        border: Border.all(
          color: themeColor,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        decoration: decoration,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  void changeCheck(bool value, AssetEntity entity) {
    if (value) {
      addSelectEntity(entity);
    } else {
      removeSelectEntity(entity);
    }
    setState(() {});
  }

  void _onGalleryChange(AssetPathEntity assetPathEntity) {
    _currentPath = assetPathEntity;

    _currentPath.assetList.then((v) async {
      _sortAssetList(v);
      list.clear();
      list.addAll(v);
      scrollController.jumpTo(0.0);
      await checkPickImageEntity();
      setState(() {});
    });
  }

  bool handlePreviewResult(List<AssetEntity> v) {
    if (v == null) {
      return false;
    }
    if (v is List<AssetEntity>) {
      return true;
    }
    return false;
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        children: <Widget>[
          Container(
            width: 40.0,
            height: 40.0,
            padding: const EdgeInsets.all(5.0),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(themeColor),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              i18nProvider.loadingText(),
              style: const TextStyle(
                fontSize: 12.0,
              ),
            ),
          ),
        ],
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
      ),
    );
  }

  void _onAssetChange() {
    if (useAlbum) {
      _onPhotoRefresh();
    }
  }

  void _onPhotoRefresh() async {
    List<AssetPathEntity> pathList;
    switch (options.pickType) {
      case PickType.onlyImage:
        pathList = await PhotoManager.getImageAsset();
        break;
      case PickType.onlyVideo:
        pathList = await PhotoManager.getVideoAsset();
        break;
      default:
        pathList = await PhotoManager.getAssetPathList();
    }

    if (pathList == null) {
      return;
    }

    this.galleryPathList.clear();
    this.galleryPathList.addAll(pathList);

    if (!this.galleryPathList.contains(this.currentPath)) {
      // current path is deleted , 当前的相册被删除, 应该提示刷新
      if (this.galleryPathList.length > 0) {
        _onGalleryChange(this.galleryPathList[0]);
      }
      return;
    }
    // Not deleted
    _onGalleryChange(this.currentPath);
  }
}
