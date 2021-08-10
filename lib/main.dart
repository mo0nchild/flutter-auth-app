import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongodb;
import 'package:bitsdojo_window/bitsdojo_window.dart';

const Color mainColor = Color.fromARGB(255, 71, 138, 255);

//set your mongodb atlas database url
const String mongodbURL = 'mongodb://<username>:<password>@' +
    'test-cluster-shard-00-00.x3kfd.mongodb.net:27017,' +
    'test-cluster-shard-00-01.x3kfd.mongodb.net:27017,' +
    'test-cluster-shard-00-02.x3kfd.mongodb.net:27017/<database>?' +
    'ssl=true&replicaSet=atlas-6l2axl-shard-0&authSource=admin&retryWrites=true&w=majority';

void main() {
  runApp(MyApp());
  doWhenWindowReady(() {
    final win = appWindow;
    final initialSize = Size(500, 600);
    win.minSize = initialSize;
    win.size = initialSize;
    win.alignment = Alignment.center;
    win.title = "Auth App";
    win.show();
  });
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Auth-App',
        home: Scaffold(
            body: WindowBorder(
                color: Colors.transparent,
                width: 0,
                child: MyWidget(
                    appBarTitle: 'Authorization',
                    contentChild: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [AuthWidget()],
                    )))),
      );
}

class WindowButtons extends StatelessWidget {
  final buttonColors = WindowButtonColors(
      iconNormal: Color(0xFFFFFFFF),
      mouseOver: Color(0xFFFFFFFF),
      mouseDown: Color(0xFFFFFFFF),
      iconMouseOver: Color(0xFF5c98ff),
      iconMouseDown: Color(0xEE5c98ff));

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(color: mainColor),
        child: Row(children: [
          MinimizeWindowButton(colors: buttonColors),
          MaximizeWindowButton(colors: buttonColors),
          CloseWindowButton(colors: buttonColors),
        ]));
  }
}

class MyWidget extends StatelessWidget {
  final Widget contentChild;
  final String appBarTitle;
  final Widget leadingButton;
  MyWidget(
      {required this.contentChild,
      required this.appBarTitle,
      Widget? leadingButton})
      : this.leadingButton = leadingButton ?? Container();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
          padding: EdgeInsets.only(
            left: 10,
          ),
          decoration: BoxDecoration(color: mainColor),
          child: WindowTitleBarBox(
              child: Row(children: [
            Text('Auth App', style: TextStyle(color: Colors.white)),
            Expanded(child: MoveWindow()),
            WindowButtons()
          ]))),
      Container(
          decoration: BoxDecoration(color: mainColor, boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(40, 40, 40, .3),
              offset: Offset(0, 8),
              blurRadius: 10,
            )
          ]),
          // padding: EdgeInsets.only(left: 20, right: 20),
          height: 50,
          child: Row(
            children: [
              Container(
                width: 50,
                child: leadingButton,
              ),
              Text(this.appBarTitle,
                  style: TextStyle(color: Colors.white, fontSize: 20))
            ],
          )),
      Expanded(
          child:
              Container(padding: EdgeInsets.all(10), child: this.contentChild))
    ]);
  }
}

enum AuthStates {
  log_in,
  not_found,
  not_correct_password,
  none,
  registered,
  already_taken
}

class AuthValues {
  final String login;
  final String password;
  static const String URL = mongodbURL;

  AuthValues({required this.login, required this.password});
  AuthValues.db({required String login, required String password})
      : this.login = login,
        this.password = password;
}

typedef AuthAction = Function(
    {required mongodb.DbCollection collection, required AuthValues auth});

// ignore: must_be_immutable
class AuthWidget extends StatefulWidget {
  final loginController = TextEditingController();
  final passwordController = TextEditingController();
  List<Map<String, dynamic>> inputFields = [], inputButtons = [];

  AuthWidget({Key? key}) : super(key: key) {
    inputFields = [
      {'label': 'Login', 'controller': loginController},
      {'label': 'Password', 'controller': passwordController}
    ];
    inputButtons = [
      {
        'label': 'Sign in',
        'onPress': () async => await mongoDbConnect(action: signInFunction)
      },
      {
        'label': 'Sign up',
        'onPress': () async => await mongoDbConnect(action: signUpFunction)
      }
    ];
  }

  Future<void> mongoDbConnect({required AuthAction action}) async {
    var login = loginController.text.replaceAll(' ', '');
    var password = passwordController.text.replaceAll(' ', '');

    //print('$login $password');

    if (login.isEmpty || password.isEmpty)
      return widgetState.toggleButtonsAvailable();
    try {
      var db = mongodb.Db(AuthValues.URL);
      await db.open(secure: true);
      //print('opened');

      var coll = db.collection('items');
      await action(
          collection: coll,
          auth: AuthValues.db(login: login, password: password));
    } catch (e) {
      print(e);
    }
    widgetState.toggleButtonsAvailable();
  }

  Future<void> signInFunction(
      {required mongodb.DbCollection collection,
      required AuthValues auth}) async {
    var items =
        await collection.find(mongodb.where.sortBy('login').skip(0)).toList();

    for (var element in items) {
      if (element['login'] == auth.login) {
        if (element['password'] == auth.password) {
          return widgetState.setAuthState(
              next: AuthStates.log_in, data: element['_id']);
        } else
          return widgetState.setAuthState(
              next: AuthStates.not_correct_password);
      }
    }
    widgetState.setAuthState(next: AuthStates.not_found);
  }

  Future<void> signUpFunction(
      {required mongodb.DbCollection collection,
      required AuthValues auth}) async {
    var items =
        await collection.find(mongodb.where.sortBy('login').skip(0)).toList();

    for (var element in items) {
      if (element['login'] == auth.login)
        return widgetState.setAuthState(next: AuthStates.already_taken);
    }
    await collection.insertOne(
        {'login': auth.login, 'password': auth.password, 'data': []});
    var value = await collection.findOne(mongodb.where.eq("login", auth.login));
    widgetState.setAuthState(next: AuthStates.registered, data: value!['_id']);
  }

  final widgetState = AuthWidgetState();
  @override
  AuthWidgetState createState() => widgetState;
}

class AuthWidgetState extends State<AuthWidget> {
  late bool buttonsAvailable;
  late AuthStates authState;
  late BuildContext myContext;

  @override
  void initState() {
    buttonsAvailable = true;
    authState = AuthStates.none;
    super.initState();
  }

  void toggleButtonsAvailable() =>
      setState(() => this.buttonsAvailable = !this.buttonsAvailable);

  void setAuthState({required AuthStates next, mongodb.ObjectId? data}) {
    setState(() => this.authState = next);
    if (this.authState == AuthStates.log_in ||
        this.authState == AuthStates.registered)
      Navigator.of(myContext).push(MaterialPageRoute(
          builder: (context) => MenuWidget(profileID: data!)));
  }

  List<Widget> renderInputFields() {
    return widget.inputFields
        .map((e) => MyInputField(
              inputController: e['controller'],
              label: e['label'],
              textFieldAvailable: buttonsAvailable,
              replaceSpace: true,
            ))
        .toList();
  }

  List<Widget> renderInputButtons() {
    return widget.inputButtons
        .map((e) => MyInputButton(
            label: e['label'],
            buttonAvailable: this.buttonsAvailable,
            onPressAction: () {
              if (buttonsAvailable) {
                toggleButtonsAvailable();
                e['onPress']();
              }
            }))
        .toList();
  }

  Widget renderCentredWidget({required List<Widget> children}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }

  Widget renderMainWidget() {
    return Column(children: [
      Opacity(
        opacity: (this.buttonsAvailable) ? 1 : .6,
        child: renderCentredWidget(children: [
          Column(
            children: renderInputFields(),
          ),
          Container(
            margin: EdgeInsets.all(0),
            padding: EdgeInsets.only(right: 50, left: 50),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: renderInputButtons(),
            ),
          ),
          Container(
              margin: EdgeInsets.only(top: 10, bottom: 10),
              child: Text(
                authState.toString(),
                style: TextStyle(color: Colors.white),
              ))
        ]),
      ),
      (!this.buttonsAvailable)
          ? LinearProgressIndicator(
              color: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              backgroundColor: Colors.transparent,
            )
          : Container(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    this.myContext = context;
    return Container(
        decoration: BoxDecoration(
          color: mainColor,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.all(const Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(20, 20, 20, .3),
              offset: Offset(0, 0),
              blurRadius: 10,
            )
          ],
        ),
        height: 300,
        width: 350,
        padding: EdgeInsets.only(bottom: 0, left: 30, right: 30, top: 30),
        child: renderMainWidget());
  }
}

class MyInputButton extends StatelessWidget {
  final String label;
  final bool buttonAvailable;
  final Color color;
  final Function onPressAction;
  const MyInputButton(
      {Key? key,
      required this.label,
      Color? color,
      bool? buttonAvailable,
      required this.onPressAction})
      : this.buttonAvailable = buttonAvailable ?? true,
        this.color = color ?? Colors.white,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => onPressAction(),
      child: Text(
        this.label,
        style: TextStyle(color: this.color, fontSize: 15),
      ),
      style: ButtonStyle(
          mouseCursor: MaterialStateProperty.all((this.buttonAvailable)
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic),
          shape: MaterialStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15.0),
              side: BorderSide(color: this.color))),
          padding: MaterialStateProperty.all(EdgeInsets.all(20))),
    );
  }
}

class MyInputField extends StatelessWidget {
  final TextEditingController inputController;
  final String label;
  final int length, lines;
  final bool textFieldAvailable, replaceSpace;
  final OutlineInputBorder border = OutlineInputBorder(
      borderSide: BorderSide(
        color: Colors.white,
      ),
      borderRadius: BorderRadius.all(Radius.circular(10)));
  MyInputField(
      {required this.inputController,
      required this.label,
      int? length,
      int? lines,
      bool? textFieldAvailable,
      bool? replaceSpace})
      : this.textFieldAvailable = textFieldAvailable ?? true,
        this.length = length ?? 25,
        this.lines = lines ?? 1,
        this.replaceSpace = replaceSpace ?? false;

  String get inputFieldText => inputController.text;

  @override
  Widget build(BuildContext context) {
    return Theme(
        data: ThemeData(
            textSelectionTheme: TextSelectionThemeData(
                cursorColor: Colors.white,
                selectionColor: Colors.white.withOpacity(.2))),
        child: Container(
          margin: EdgeInsets.only(bottom: 10),
          child: TextField(
            inputFormatters: this.replaceSpace
                ? [FilteringTextInputFormatter.allow(RegExp('[a-z]'))]
                : null,
            enabled: textFieldAvailable,
            decoration: InputDecoration(
                counterStyle: TextStyle(color: Colors.white),
                border: UnderlineInputBorder(),
                labelText: label,
                labelStyle: TextStyle(color: Colors.white),
                filled: false,
                focusedBorder: border,
                enabledBorder: border,
                disabledBorder: border),
            style: TextStyle(color: Colors.white),
            controller: inputController,
            maxLength: this.length,
            maxLines: this.lines,
            minLines: this.lines,
          ),
        ));
  }
}

// ignore: must_be_immutable
class MenuWidget extends StatefulWidget {
  final mongodb.ObjectId profileID;
  final double elementsMaxWidth = 1300;

  MenuWidget({Key? key, required this.profileID}) : super(key: key);

  Future<void> connectDB(
      {required Function action,
      required String title,
      required String post,
      bool? emptyCheck}) async {
    var updTitle = title.replaceAll(' ', '');
    var updPost = post.replaceAll(' ', '');

    if ((updTitle.isEmpty || updPost.isEmpty) && (emptyCheck ?? true)) return;
    widgetState.toggleState();

    try {
      var db = mongodb.Db(AuthValues.URL);
      await db.open();
      await action(db.collection('items'));
    } catch (e) {
      print(e);
    }
    widgetState.toggleState();
  }

  _MenuWidgetState widgetState = _MenuWidgetState();
  @override
  _MenuWidgetState createState() => widgetState;
}

class _MenuWidgetState extends State<MenuWidget> {
  final titleController = TextEditingController();
  final postController = TextEditingController();
  bool availableState = true;
  List<dynamic> items = [];

  @override
  void initState() {
    reloadPostList();
    super.initState();
  }

  BoxShadow renderBoxShadow() => BoxShadow(
        color: Color.fromRGBO(20, 20, 20, .3),
        offset: Offset(0, 0),
        blurRadius: 10,
      );

  void toggleState() =>
      setState(() => this.availableState = !this.availableState);

  Future<void> publishPost() async {
    var title = titleController.text.replaceAll(' ', '');
    await widget.connectDB(
        action: (coll) async {
          var list = this.items;
          list.insert(0, {'title': title, 'post': postController.text});
          await coll.updateMany(mongodb.where.eq('_id', widget.profileID),
              mongodb.modify.set('data', list));
          titleController.text = '';
          postController.text = '';
          setState(() => this.items = list);
        },
        title: title,
        post: postController.text);
  }

  Future<void> deletePost({required int index}) async {
    var title = titleController.text.replaceAll(' ', '');
    await widget.connectDB(
        action: (coll) async {
          var list = this.items;
          list.removeAt(index);
          await coll.updateMany(mongodb.where.eq('_id', widget.profileID),
              mongodb.modify.set('data', list));
          setState(() => this.items = list);
        },
        title: title,
        emptyCheck: false,
        post: postController.text);
  }

  Future<void> reloadPostList() async {
    var title = titleController.text.replaceAll(' ', '');
    await widget.connectDB(
        action: (coll) async {
          //print(widget.profileID);
          var user = await coll
              .find(mongodb.where.eq('_id', widget.profileID))
              .toList();

          List<dynamic> list = user[0]['data'];
          setState(() => this.items = list);
        },
        emptyCheck: false,
        post: postController.text,
        title: title);
  }

  Widget renderInputWidget() {
    var content = Row(children: [
      Expanded(
          child: MyInputField(
              inputController: titleController,
              label: 'Title',
              replaceSpace: true,
              textFieldAvailable: this.availableState)),
      Container(
          padding: EdgeInsets.only(bottom: 30),
          margin: EdgeInsets.only(left: 30),
          child: MyInputButton(
              buttonAvailable: this.availableState,
              label: 'Publish',
              onPressAction: () async => await publishPost())),
      Container(
          padding: EdgeInsets.only(bottom: 30),
          child: Container(
              padding: EdgeInsets.all(2),
              margin: EdgeInsets.only(left: 20),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(20)),
              child: IconButton(
                icon: Icon(Icons.restart_alt_rounded, color: Colors.white),
                onPressed: () async => await reloadPostList(),
              ))),
    ]);

    return Container(
      height: 256,
      constraints: BoxConstraints(maxWidth: widget.elementsMaxWidth),
      decoration: BoxDecoration(
          color: mainColor,
          boxShadow: [renderBoxShadow()],
          borderRadius: BorderRadius.all(Radius.circular(20))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Opacity(
            opacity: (this.availableState) ? 1 : .6,
            child: Column(
              children: [
                content,
                Container(
                    child: MyInputField(
                  inputController: postController,
                  label: 'Post',
                  lines: 3,
                  length: 100,
                  textFieldAvailable: this.availableState,
                )),
              ],
            ),
          ),
          (!this.availableState)
              ? LinearProgressIndicator(
                  color: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  backgroundColor: Colors.transparent,
                )
              : Container(),
        ],
      ),
      padding: EdgeInsets.only(bottom: 10, right: 20, top: 20, left: 20),
      margin: EdgeInsets.all(30),
    );
  }

  Widget renderListView() {
    var content = ({required String title, required int index}) => Container(
          height: 80,
          padding: EdgeInsets.all(15),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Text('Title: $title',
                  style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            Container(
                child: Row(children: [
              MyInputButton(
                buttonAvailable: this.availableState,
                label: 'Open',
                onPressAction: () =>
                    Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => ReadPostTab(
                    post: this.items[index]['post'],
                    title: this.items[index]['title'],
                  ),
                )),
              ),
              Container(
                  margin: EdgeInsets.only(left: 10),
                  child: MyInputButton(
                    buttonAvailable: this.availableState,
                    label: 'Delete',
                    onPressAction: () async => await deletePost(index: index),
                    color: Colors.red[400],
                  ))
            ])),
          ]),
        );

    return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          return Card(
              margin: EdgeInsets.only(bottom: 20, right: 20),
              shadowColor: Color.fromRGBO(20, 20, 20, .4),
              color: mainColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Opacity(
                opacity: this.availableState ? 1 : .6,
                child: content(title: this.items[index]['title'], index: index),
              ));
        });
  }

  Widget renderListWidget(BuildContext context) {
    var emptyWidget = Container(
        constraints: BoxConstraints(maxWidth: widget.elementsMaxWidth),
        child: Flex(
            direction: Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                  child: Center(
                child: Text('Empty',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mainColor, fontSize: 90)),
              ))
            ]));

    return Container(
        padding: EdgeInsets.only(bottom: 15, top: 15, left: 15, right: 10),
        margin: EdgeInsets.only(bottom: 20, right: 30, left: 30),
        constraints: BoxConstraints(maxWidth: widget.elementsMaxWidth),
        decoration: BoxDecoration(
            color: Colors.white70,
            boxShadow: [renderBoxShadow()],
            border:
                Border.all(color: Color.fromRGBO(43, 149, 255, .8), width: 5),
            borderRadius: BorderRadius.all(Radius.circular(20))),
        child: Theme(
          data: ThemeData(
            scrollbarTheme: ScrollbarThemeData(
              thumbColor: MaterialStateProperty.all(mainColor),
            ),
          ),
          child: (items.length == 0)
              ? emptyWidget
              : Scrollbar(
                  isAlwaysShown: true, thickness: 10, child: renderListView()),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MyWidget(
          appBarTitle: 'Profile',
          contentChild: SafeArea(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.start, children: [
              renderInputWidget(),
              Expanded(flex: 2, child: renderListWidget(context)),
            ]),
          ),
          leadingButton: IconButton(
            icon: Icon(
              Icons.logout_rounded,
              color: Colors.white,
              size: 15,
            ),
            onPressed: () => Navigator.pop(context),
          )),
    );
  }
}

class ReadPostTab extends StatelessWidget {
  final String post, title;
  const ReadPostTab({required this.post, required this.title, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MyWidget(
          appBarTitle: title,
          contentChild: SafeArea(
            child: Container(
              margin: EdgeInsets.only(top: 30, right: 25, left: 25),
              child:
                  Text(post, style: TextStyle(color: mainColor, fontSize: 20)),
            ),
          ),
          leadingButton: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 15,
            ),
            onPressed: () => Navigator.pop(context),
          )),
    );
  }
}
