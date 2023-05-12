# Why? I wanted to use an app without Siri/Shortcuts/Etc integration and it was a good learning experience

So I figured out a handful of ways to get what I wanted done

But I thought the most interesting would be to send fake touch events

I found that there are a few resources out there for sending touch events like https://github.com/lyft/Hammer

But to get this compiled and into a dynamic library you need to link with XCTest for some of the functionality

You can actually rip the XCTest code out of https://github.com/lyft/Hammer and it will still work

But I wanted to see if I could get by all this.

So I wrote this tool to go and get all the dependencies of XCTest.. all the Private Frameworks and dylibs and setup the linker info (rpath)  so that everything worked



The library I use here is poorly named.. I was going to hook the url open not from Frida but with ObjC hooking..

With the app being SwiftUI I found it easiest to just do with Frida.. So libHandleURLScheme is really just Lyfts Hammer repo with an ObjC Bridge so you can
easily use it from Frida. It can be found at:


https://github.com/bebrws/dylibForSendingKeyboardTouchEvents



# Example usage:
```
rm -rf deps; ./gatherAndFixLibs.sh ./libHandleURLScheme.dylib
cp lib deps
```

Then copy all the of the files in deps to your apps Frameworks folder along with the dylib you are injecting
Which is the arg to this script


An example usage:

rm -rf ~/Payload
unzip some-decrypted-app.ipa

insert_dylib --strip-codesig --inplace '@executable_path/Frameworks/libHandleURLScheme.dylib' ~/Payload/SomeApp.app/SomeApp
cp -r ~/deps/* ~/Payload/SomeApp.app/Frameworks
rm ~/Payload/SomeApp.app/Frameworks/.DS_Store
rm ~/Payload/.DS_Store

rm -rf SomeAppURLScheme.ipa; zip -vr SomeAppURLScheme.ipa Payload
objection patchipa --source ./SomeAppURLScheme.ipa --codesign-signature EDF05F987F947D7781F6EC4902567E238C2BD34D -P iphone7-embedded.mobileprovision
rm -rf Payload
unzip SomeAppURLScheme-frida-codesigned.ipa

### Run it:

ios-deploy --bundle Payload/SomeApp.app -W -d -v  # -d will start lldb /  debug server  on start


Then connect with frida:

```
frida -U SomeApp
```
 and run:


```
ObjC.classes["HandleURLScheme.BBEvent"]["+ sendTouchWindowAtX:y:"](50,100)
ObjC.classes["HandleURLScheme.BBEvent"]["+ sendTouchWindowAtX:y:"](-180,-330)

```

OR what I am doing is using the frida gadget script option to hook and add a url scheme so I can do stuff like use this app with shortcuts and integrate with it in other ways.

# Setting up FridaGadget to run at start:

Create file in Frameworks dir:

FridaGadget.config:
```
{
  "interaction": {
    "type": "script",
    "path": "someapp.js",
    "on_change": "reload"
  }
}
```

In the Frameworks dir also have a file someapp.js:

```
rpc.exports = {
    init(stage, parameters) {
        console.error('[init]', stage, JSON.stringify(parameters));

        var globalar = null;

        var NSLog = new NativeFunction(Module.findExportByName('Foundation', 'NSLog'), 'void', ['pointer', '...']);
        var NSString = ObjC.classes.NSString;
        var str = NSString.stringWithFormat_("[*] BRAD IN FRIDA GADGET");
        NSLog(str);
        console.error("[*] BRAD IN FRIDA GADGET");

        var NSJSONSerialization = ObjC.classes.NSJSONSerialization;
        var NSUTF8StringEncoding = 4;

        var NSURL = ObjC.classes.NSURL;

        var scenes = ObjC.classes.UIApplication.sharedApplication().connectedScenes();

        var winSceneRegex = /UIWindowScene: (0x[a-fA-F0-9]+)/
        var scenesPtr = ptr(scenes.toString().match(winSceneRegex)[1]);
        var windowScene = ObjC.Object(scenesPtr);
        try {
            if (!scenes) {
                console.error("Couldn't file UIWindowScene on sharedApplication");
            } else {
                Interceptor.attach(windowScene.delegate()["- scene:openURLContexts:"].implementation, {
                    onEnter(args) {
                        // ObjC: args[0] = self, args[1] = selector, args[2-n] = arguments
                        const arg2Str = new ObjC.Object(args[2]);
                        console.error("String argument: " + arg2Str.toString());
                        NSLog(NSString.stringWithFormat_("[*] BRAD scene:openURLContexts: argument 2: " + arg2Str.toString()));

                        const arg3Str = new ObjC.Object(args[3]);
                        console.error("String argument: " + arg3Str.toString());
                        NSLog(NSString.stringWithFormat_("[*] BRAD scene:openURLContexts: argument 3: " + arg3Str.toString()));

                        globalar = arg3Str;
                        var someappActionFromURLRegex = /URL: someapp:\/\/(\S+)/; ///.*URL: someapp: \/\/([a-z]*);.*/;
                        console.error(arg3Str.toString().match(someappActionFromURLRegex));
                        var action = arg3Str.toString().match(someappActionFromURLRegex)[1];

                        // Do something here!! Like send a touch event to the middle of the screen with:
                        ObjC.classes["HandleURLScheme.BBEvent"]["+ sendTouchWindowAtX:y:"](0,0);

                    }
                });
                console.error("[*]WindowScene() intercept placed");
                NSLog(NSString.stringWithFormat_("[*]WindowScene() intercept placed"));
            }
        }
        catch (err) {
            console.error("[*]BRAD Exception: " + err.message);
            NSLog(NSString.stringWithFormat_("[*]BRAD Exception: " + err.message));
        }

        NSLog(NSString.stringWithFormat_("[*]BRAD Set the hook for openURL"));


    },
    dispose() {
        console.error('[dispose]');
    }
};


```
