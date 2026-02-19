importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDSj-VgMO00ImwLFEFJ5JoVWpYzHUFKfm8',
  authDomain: 'sistemacompraschabely.firebaseapp.com',
  databaseURL: 'https://sistemacompraschabely-default-rtdb.firebaseio.com',
  projectId: 'sistemacompraschabely',
  storageBucket: 'sistemacompraschabely.firebasestorage.app',
  messagingSenderId: '646841655886',
  appId: '1:646841655886:web:98198b772ddcdd3902991f',
  measurementId: 'G-N8EJKZXG1X',
});

firebase.messaging();
