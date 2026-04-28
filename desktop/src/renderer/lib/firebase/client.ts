import { initializeApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getDatabase } from "firebase/database";
import { getStorage } from "firebase/storage";

const firebaseConfig = {
  apiKey: "AIzaSyDqGlqXBMHtpBBWX80MDNJXiFkU89spXpg",
  appId: "1:130125072749:web:05e7f238d9c1173d8b7264",
  messagingSenderId: "130125072749",
  projectId: "compraschabelyacerpro",
  authDomain: "compraschabelyacerpro.firebaseapp.com",
  databaseURL: "https://compraschabelyacerpro-default-rtdb.firebaseio.com",
  storageBucket: "compraschabelyacerpro.firebasestorage.app",
  measurementId: "G-9TXERRMC45",
};

export const firebaseApp = initializeApp(firebaseConfig);
export const auth = getAuth(firebaseApp);
export const database = getDatabase(firebaseApp);
export const storage = getStorage(firebaseApp);
