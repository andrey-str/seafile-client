//
// Created by Andrey Streltsov on 18/05/15.
//

#ifndef SEAFILE_CLIENT_RENDERSTAB_H
#define SEAFILE_CLIENT_RENDERSTAB_H


#include <qwebview.h>
#include "tab-view.h"

class RendersTab : public TabView {

Q_OBJECT

public:
    explicit RendersTab(QWidget *parent=0);
public:

    void refresh();
    void startRefresh();
    void stopRefresh();

    void createWebKitView();
private:
    QWidget* _webViewWidget;
    QWebView* _webView;
};


#endif //SEAFILE_CLIENT_RENDERSTAB_H
