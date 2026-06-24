import { initializeApp } from "firebase/app";
import { getFirestore, collection, getDocs } from "firebase/firestore";

const firebaseConfig = {
  apiKey: "AIzaSyB7Nz5o4XcZ1waXsKSEDiiSJRU_xt2oIzE",
  authDomain: "runaapp-cca6a.firebaseapp.com",
  projectId: "runaapp-cca6a",
  storageBucket: "runaapp-cca6a.firebasestorage.app",
  messagingSenderId: "787850092507",
  appId: "1:787850092507:web:04dbee19af71b0808b51fe",
  measurementId: "G-QWCSG6F5YR"
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);

async function testRead() {
  console.log("Mencoba membaca koleksi 'users' menggunakan Client Key...");
  try {
    const querySnapshot = await getDocs(collection(db, "users"));
    console.log(`Berhasil! Ditemukan ${querySnapshot.size} users.`);
    querySnapshot.forEach((doc) => {
      console.log(doc.id, " => ", doc.data().username || doc.data().email);
    });
  } catch (error) {
    console.error("Gagal membaca Firestore:", error.message);
  }
}

testRead();
