#include <windows.h>
#include <shlwapi.h>
#include <vector>


#include "registry.h"

namespace {

LONG openKey(HKEY root, const QString& path, HKEY *p_key)
{
    LONG result;
    result = RegOpenKeyExW(root,
                           path.toStdWString().c_str(),
                           0L,
                           KEY_ALL_ACCESS,
                           p_key);

    return result;
}

} // namespace

RegElement::RegElement(const HKEY& root, const QString& path,
                       const QString& name, const QString& value, bool expand)
    : root_(root),
      path_(path),
      name_(name),
      string_value_(value),
      dword_value_(0),
      type_(expand ? REG_EXPAND_SZ : REG_SZ)
{
}

RegElement::RegElement(const HKEY& root, const QString& path,
                       const QString& name, DWORD value)
    : root_(root),
      path_(path),
      name_(name),
      string_value_(""),
      dword_value_(value),
      type_(REG_DWORD)
{
}

int RegElement::openParentKey(HKEY *pKey)
{
    DWORD disp;
    HRESULT result;

    result = RegCreateKeyExW (root_,
                              path_.toStdWString().c_str(),
                              0, NULL,
                              REG_OPTION_NON_VOLATILE,
                              KEY_WRITE | KEY_WOW64_64KEY,
                              NULL,
                              pKey,
                              &disp);

    if (result != ERROR_SUCCESS) {
        return -1;
    }

    return 0;
}

int RegElement::add()
{
    HKEY parent_key;
    DWORD value_len;
    LONG result;

    if (openParentKey(&parent_key) < 0) {
        return -1;
    }

    if (type_ == REG_SZ || type_ == REG_EXPAND_SZ) {
        // See http://msdn.microsoft.com/en-us/library/windows/desktop/ms724923(v=vs.85).aspx
        value_len = sizeof(wchar_t) * (string_value_.toStdWString().length() + 1);
        result = RegSetValueExW (parent_key,
                                 name_.toStdWString().c_str(),
                                 0, REG_SZ,
                                 (const BYTE *)(string_value_.toStdWString().c_str()),
                                 value_len);
    } else {
        value_len = sizeof(dword_value_);
        result = RegSetValueExW (parent_key,
                                 name_.toStdWString().c_str(),
                                 0, REG_DWORD,
                                 (const BYTE *)&dword_value_,
                                 value_len);
    }

    if (result != ERROR_SUCCESS) {
        return -1;
    }

    return 0;
}

int RegElement::removeRegKey(HKEY root, const QString& path, const QString& subkey)
{
    HKEY hKey;
    LONG result = RegOpenKeyExW(root,
                                path.toStdWString().c_str(),
                                0L,
                                KEY_ALL_ACCESS,
                                &hKey);

    if (result != ERROR_SUCCESS) {
        return -1;
    }

    result = SHDeleteKeyW(hKey, subkey.toStdWString().c_str());
    if (result != ERROR_SUCCESS) {
        return -1;
    }

    return 0;
}

bool RegElement::exists()
{
    HKEY parent_key;
    LONG result = openKey(root_, path_, &parent_key);
    if (result != ERROR_SUCCESS) {
        return false;
    }

    char buf[MAX_PATH] = {0};
    DWORD len = sizeof(buf);
    result = RegQueryValueExW (parent_key,
                               name_.toStdWString().c_str(),
                               NULL,             /* reserved */
                               NULL,             /* output type */
                               (LPBYTE)buf,      /* output data */
                               &len);            /* output length */

    RegCloseKey(parent_key);
    if (result != ERROR_SUCCESS) {
        return false;
    }

    return true;
}

void RegElement::read()
{
    string_value_.clear();
    dword_value_ = 0;
    HKEY parent_key;
    LONG result = openKey(root_, path_, &parent_key);
    if (result != ERROR_SUCCESS) {
        return;
    }
    const std::wstring std_name = name_.toStdWString();

    DWORD len;
    // get value size
    result = RegQueryValueExW (parent_key,
                               std_name.c_str(),
                               NULL,             /* reserved */
                               &type_,           /* output type */
                               NULL,             /* output data */
                               &len);            /* output length */
    if (result != ERROR_SUCCESS) {
        RegCloseKey(parent_key);
        return;
    }
    // get value
    std::vector<wchar_t> buf;
    buf.resize(len);
    result = RegQueryValueExW (parent_key,
                               std_name.c_str(),
                               NULL,             /* reserved */
                               &type_,           /* output type */
                               (LPBYTE)&buf[0],  /* output data */
                               &len);            /* output length */
    buf.resize(len);
    if (result != ERROR_SUCCESS) {
        RegCloseKey(parent_key);
        return;
    }

    switch (type_) {
        case REG_EXPAND_SZ:
        case REG_SZ:
            string_value_ = QString::fromWCharArray(&buf[0], buf.size());
            break;
        case REG_NONE:
        case REG_BINARY:
            string_value_ = QString::fromWCharArray(&buf[0], buf.size() / 2);
            break;
        case REG_DWORD_BIG_ENDIAN:
        case REG_DWORD:
            if (buf.size() != sizeof(int))
                return;
            memcpy((char*)&dword_value_, buf.data(), sizeof(int));
            break;
        case REG_QWORD: {
            if (buf.size() != sizeof(int))
                return;
            qint64 value;
            memcpy((char*)&value, buf.data(), sizeof(int));
            dword_value_ = (int)value;
            break;
        }
        case REG_MULTI_SZ:
        default:
          break;
    }

    RegCloseKey(parent_key);

    // workaround with a bug
    string_value_ = QString::fromUtf8(string_value_.toUtf8());

    return;
}

void RegElement::remove()
{
    HKEY parent_key;
    LONG result = openKey(root_, path_, &parent_key);
    if (result != ERROR_SUCCESS) {
        return;
    }
    result = RegDeleteValueW (parent_key, name_.toStdWString().c_str());
    RegCloseKey(parent_key);
}
