# React Native SQLCipher 2

SQLCipher Native Plugin for React Native for Android/iOS/Windows.
This plugin provides a [WebSQL](http://www.w3.org/TR/webdatabase/)-compatible API to store data in a react native app, by using a SQLCipher database on the native side.

Forked from [React native SQlite 2](https://github.com/craftzdog/react-native-sqlite-2)

## Getting started

```shell
$ npm install react-native-sqlcipher-2 --save
```

### Mostly automatic installation

```shell
$ react-native link react-native-sqlcipher-2
```

#### Additional step for iOS

Add the following to your Podfile
```
pod 'SQLCipher'
```

## Usage

```javascript
import SQLite from 'react-native-sqlcipher-2';

const db = SQLite.openDatabase('{ name: "test.db", password: "testpassword" }', '1.0', '', 1);
db.transaction(function (txn) {
  txn.executeSql('DROP TABLE IF EXISTS Users', []);
  txn.executeSql('CREATE TABLE IF NOT EXISTS Users(user_id INTEGER PRIMARY KEY NOT NULL, name VARCHAR(30))', []);
  txn.executeSql('INSERT INTO Users (name) VALUES (:name)', ['nora']);
  txn.executeSql('INSERT INTO Users (name) VALUES (:name)', ['takuya']);
  txn.executeSql('SELECT * FROM `users`', [], function (tx, res) {
    for (let i = 0; i < res.rows.length; ++i) {
      console.log('item:', res.rows.item(i));
    }
  });
});
```

There is a test app in the [test directory](https://github.com/sreejithkrishnanr/react-native-sqlite-2/tree/master/test).

### Using with PouchDB

It can be used with [pouchdb-adapter-react-native-sqlite](https://github.com/sreejithkrishnanr/react-native-sqlite-2).

```javascript
import PouchDB from 'pouchdb-react-native'
import SQLite from 'react-native-sqlcipher-2'
import SQLiteAdapterFactory from 'pouchdb-adapter-react-native-sqlite'

const SQLiteAdapter = SQLiteAdapterFactory(SQLite)
PouchDB.plugin(SQLiteAdapter)
var db = new PouchDB('{ name: "test.db", password: "testpassword" }', { adapter: 'react-native-sqlite' })
```

